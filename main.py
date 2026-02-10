import os
import logging
import base64
import tempfile
import uuid
from fastapi import FastAPI, HTTPException, Request
from fastapi.responses import FileResponse
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel
from slowapi import Limiter, _rate_limit_exceeded_handler
from slowapi.util import get_remote_address
from slowapi.errors import RateLimitExceeded
import yt_dlp

# --- Logging Setup ---
logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [%(levelname)s] %(message)s",
    datefmt="%Y-%m-%d %H:%M:%S",
)
logger = logging.getLogger("video_downloader")

# --- App Init ---
limiter = Limiter(key_func=get_remote_address)
app = FastAPI(title="Video Downloader API", version="2.0.0")
app.state.limiter = limiter
app.add_exception_handler(RateLimitExceeded, _rate_limit_exceeded_handler)

# --- CORS ---
ALLOWED_ORIGINS = os.getenv("ALLOWED_ORIGINS", "*").split(",")
app.add_middleware(
    CORSMiddleware,
    allow_origins=ALLOWED_ORIGINS,
    allow_methods=["GET", "POST"],
    allow_headers=["*"],
)

# --- Legacy file serving (kept for backward compatibility) ---
DOWNLOAD_DIR = "downloads"
os.makedirs(DOWNLOAD_DIR, exist_ok=True)


class VideoRequest(BaseModel):
    url: str
    cookies: str | None = None  # Optional base64-encoded Netscape cookies


# =====================
# Health Check Endpoints
# =====================

@app.get("/")
def root():
    return {"status": "ok", "service": "video-downloader-api", "version": "2.0.0"}


@app.get("/health")
def health_check():
    return {"status": "healthy"}


# =====================
# Link Extraction (Core)
# =====================

def _get_cookie_file(request_cookies_b64: str | None) -> str | None:
    """
    Resolve cookie file path. Priority:
      1. Per-request base64 cookies from client
      2. INSTAGRAM_COOKIES env var (base64)
      3. None (no cookies)
    """
    raw = request_cookies_b64 or os.getenv("INSTAGRAM_COOKIES")
    if not raw:
        return None

    try:
        decoded = base64.b64decode(raw).decode("utf-8")
        tmp = tempfile.NamedTemporaryFile(
            mode="w", suffix=".txt", delete=False, prefix="cookies_"
        )
        tmp.write(decoded)
        tmp.close()
        return tmp.name
    except Exception as e:
        logger.warning("Failed to decode cookies: %s", e)
        return None


@app.post("/extract")
@limiter.limit("10/minute")
def extract_info(request: VideoRequest, req: Request):
    """
    Extract direct media URL and metadata.
    Returns JSON with direct_url for client-side downloading.
    """
    url = request.url.strip()
    if not url.startswith("http"):
        raise HTTPException(status_code=400, detail="Invalid URL. Must start with http(s).")

    cookie_file = _get_cookie_file(request.cookies)

    ydl_opts = {
        "quiet": True,
        "ignoreerrors": True,
        "noplaylist": True,
        "extract_flat": False,
        "skip_download": True,
        "user_agent": (
            "Mozilla/5.0 (Windows NT 10.0; Win64; x64) "
            "AppleWebKit/537.36 (KHTML, like Gecko) "
            "Chrome/120.0.0.0 Safari/537.36"
        ),
    }

    if cookie_file:
        ydl_opts["cookiefile"] = cookie_file

    try:
        logger.info("Analyzing URL: %s", url)

        with yt_dlp.YoutubeDL(ydl_opts) as ydl:
            info = ydl.extract_info(url, download=False)

            if info is None:
                raise HTTPException(
                    status_code=400,
                    detail="Could not extract info. The URL may be invalid or require login.",
                )

            # Handle carousels / playlists — pick first entry
            if "entries" in info:
                logger.info("Detected carousel/playlist, picking first entry.")
                try:
                    info = list(info["entries"])[0]
                except (IndexError, StopIteration):
                    raise HTTPException(status_code=400, detail="Empty playlist/carousel.")

            # Determine media type
            is_video = True
            if info.get("vcodec") == "none" or info.get("ext") in [
                "jpg", "jpeg", "png", "webp", "heic",
            ]:
                is_video = False

            # Get the best direct URL
            direct_url = info.get("url")

            # For videos, try to get the best format URL
            if is_video and not direct_url:
                formats = info.get("formats", [])
                if formats:
                    # Pick best quality with both video+audio, fallback to last
                    best = None
                    for f in formats:
                        if f.get("vcodec") != "none" and f.get("acodec") != "none":
                            best = f
                    if best is None:
                        best = formats[-1]
                    direct_url = best.get("url")

            # For images, try thumbnail as fallback
            if not is_video and not direct_url:
                thumbnails = info.get("thumbnails", [])
                if thumbnails:
                    direct_url = thumbnails[-1].get("url")

            if not direct_url:
                raise HTTPException(
                    status_code=400,
                    detail="Could not find a direct media URL for this content.",
                )

            ext = info.get("ext", "mp4" if is_video else "jpg")
            if ext == "none":
                ext = "jpg"

            media_type = "video" if is_video else "image"
            title = info.get("title", "Media")
            # Sanitize title
            title = "".join(c for c in title if c.isalnum() or c in " _-").strip()[:100]

            logger.info(
                "Extracted %s: title='%s', ext='%s'", media_type, title, ext
            )

            return {
                "status": "success",
                "title": title or "Media",
                "direct_url": direct_url,
                "ext": ext,
                "media_type": media_type,
            }

    except HTTPException:
        raise
    except Exception as e:
        logger.error("Extraction failed: %s", str(e))
        raise HTTPException(status_code=400, detail=str(e))
    finally:
        # Clean up temp cookie file
        if cookie_file and os.path.exists(cookie_file):
            try:
                os.remove(cookie_file)
            except OSError:
                pass


# =====================
# Legacy File Serving (backward compat)
# =====================

@app.get("/get_file/{filename}")
@limiter.limit("20/minute")
def get_file(filename: str, request: Request):
    """Serve a previously downloaded file. Includes path traversal protection."""
    # Path traversal protection
    safe_name = os.path.basename(filename)
    file_path = os.path.join(DOWNLOAD_DIR, safe_name)
    real_path = os.path.realpath(file_path)
    real_dir = os.path.realpath(DOWNLOAD_DIR)

    if not real_path.startswith(real_dir):
        logger.warning("Path traversal attempt blocked: %s", filename)
        raise HTTPException(status_code=403, detail="Access denied.")

    if not os.path.exists(real_path):
        raise HTTPException(status_code=404, detail="File not found or expired.")

    return FileResponse(real_path)


# =====================
# Entry Point
# =====================

if __name__ == "__main__":
    import uvicorn

    port = int(os.getenv("PORT", "8000"))
    logger.info("Starting server on port %d", port)
    uvicorn.run(app, host="0.0.0.0", port=port)