import os
import logging
import base64
import tempfile

from fastapi import FastAPI, HTTPException, Request
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
try:
    import curl_cffi
    from yt_dlp.networking.impersonate import ImpersonateTarget
    logger.info("✅ curl-cffi is installed and available.")
except ImportError:
    logger.warning("⚠️ curl-cffi is NOT installed. TikTok downloads may fail (403).")
    ImpersonateTarget = None

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
def extract_info(video_request: VideoRequest, request: Request):
    """
    Extract direct media URL and metadata.
    Returns JSON with direct_url for client-side downloading.
    """
    url = video_request.url.strip()
    if not url.startswith("http"):
        raise HTTPException(status_code=400, detail="Invalid URL. Must start with http(s).")

    cookie_file = _get_cookie_file(video_request.cookies)

    ydl_opts = {
        "quiet": False,  # Enable output for debugging
        "verbose": True, # Enable verbose output
        "ignoreerrors": True,
        "noplaylist": True,
        "extract_flat": False,
        "skip_download": True,
        "nocheckcertificate": True, # Disable SSL checks to avoid handshake timeouts

        "user_agent": (
            "Mozilla/5.0 (Windows NT 10.0; Win64; x64) "
            "AppleWebKit/537.36 (KHTML, like Gecko) "
            "Chrome/120.0.0.0 Safari/537.36"
        ),
        "extractor_args": {
            "youtube": {
                "player_client": ["android", "web"],
                "player_skip": ["web_safari", "web_creator"],
            }
        },
        "http_headers": {
            "User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/121.0.0.0 Safari/537.36",
            "Accept": "text/html,application/xhtml+xml,application/xml;q=0.9,image/avif,image/webp,image/apng,*/*;q=0.8",
            "Accept-Language": "en-US,en;q=0.9",
            "Sec-Fetch-Mode": "navigate",
            "Sec-Fetch-Site": "none",
            "Sec-Fetch-Dest": "document",
            "Upgrade-Insecure-Requests": "1",
        },
    }

    # Only use impersonation (curl_cffi) for TikTok
    if "tiktok.com" in url.lower() and ImpersonateTarget:
        ydl_opts["impersonate"] = ImpersonateTarget(client="chrome")

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
            http_headers = info.get("http_headers", {})

            # For videos, try to get the best format URL (Prioritize MP4 with Audio+Video)
            if is_video and not direct_url:
                formats = info.get("formats", [])
                if formats:
                    best = None
                    # First pass: Look for mp4 with both audio and video
                    for f in formats:
                        if (f.get("vcodec") != "none" and 
                            f.get("acodec") != "none" and 
                            f.get("ext") == "mp4"):
                            best = f
                            # Keep looking for a better quality one (formats are usually sorted)
                    
                    # Second pass: If no mp4, look for any container with both
                    if best is None:
                        for f in formats:
                            if f.get("vcodec") != "none" and f.get("acodec") != "none":
                                best = f
                    
                    # Fallback
                    if best is None:
                        best = formats[-1]
                        
                    direct_url = best.get("url")
                    # Update headers if specific format has them
                    if best.get("http_headers"):
                        http_headers = best.get("http_headers")

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
            
            # Force mp4 ext if the url is mp4 but metadata says otherwise
            if is_video and ".mp4" in direct_url:
                 ext = "mp4"

            media_type = "video" if is_video else "image"
            title = info.get("title", "Media")
            # Sanitize title
            title = "".join(c for c in title if c.isalnum() or c in " _-").strip()[:100]

            # Ensure headers are populated
            if not http_headers:
                http_headers = {}
            
            # Force User-Agent if missing
            if "User-Agent" not in http_headers:
                http_headers["User-Agent"] = ydl_opts.get("user_agent")
            
            # Force Referer for TikTok if missing (often required)
            if "tiktok.com" in url.lower() and "Referer" not in http_headers:
                http_headers["Referer"] = "https://www.tiktok.com/"

            logger.info(
                "Extracted %s: title='%s', ext='%s'", media_type, title, ext
            )

            return {
                "status": "success",
                "title": title or "Media",
                "direct_url": direct_url,
                "ext": ext,
                "media_type": media_type,
                "headers": http_headers  # Pass headers to client
            }

    except HTTPException:
        raise
    except Exception as e:
        import traceback
        logger.error("Extraction failed: %s\n%s", str(e), traceback.format_exc())
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




# =====================
# Entry Point
# =====================

if __name__ == "__main__":
    import uvicorn

    port = int(os.getenv("PORT", "8000"))
    logger.info("Starting server on port %d", port)
    uvicorn.run(app, host="0.0.0.0", port=port)