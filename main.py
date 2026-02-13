import os
import re
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
import requests as http_requests

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


def _parse_cookies_from_file(cookie_file: str | None) -> dict:
    """Parse Netscape cookie file into a dict for requests."""
    cookies = {}
    if not cookie_file:
        return cookies
    try:
        with open(cookie_file, 'r') as f:
            for line in f:
                line = line.strip()
                if line.startswith('#') or not line:
                    continue
                parts = line.split('\t')
                if len(parts) >= 7:
                    cookies[parts[5]] = parts[6]
    except Exception:
        pass
    return cookies


def _extract_instagram_image(url: str, cookie_file: str | None) -> dict | None:
    """
    Fallback: Extract image URL directly from Instagram API when yt-dlp fails.
    Uses Instagram's private API with user cookies.
    """
    # Extract shortcode from URL
    match = re.search(r'/p/([^/?]+)', url) or re.search(r'/reel/([^/?]+)', url)
    if not match:
        return None

    shortcode = match.group(1)
    cookies = _parse_cookies_from_file(cookie_file)

    headers = {
        'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/121.0.0.0 Safari/537.36',
        'X-IG-App-ID': '936619743392459',
        'X-Requested-With': 'XMLHttpRequest',
    }

    # Try Instagram's GraphQL API with cookies (works for private posts too)
    try:
        api_url = f'https://www.instagram.com/p/{shortcode}/?__a=1&__d=dis'
        logger.info("Instagram Image Fallback: Trying %s", api_url)
        resp = http_requests.get(api_url, headers=headers, cookies=cookies, timeout=15)
        logger.info("Instagram Image Fallback: Status %s", resp.status_code)

        if resp.status_code == 200:
            data = resp.json()
            items = data.get('items', [])
            if items:
                item = items[0]
                # Check for carousel_media (multi-image post)
                carousel = item.get('carousel_media', [])
                if carousel:
                    media = carousel[0]  # First image
                else:
                    media = item

                # Get image URL from image_versions2
                candidates = media.get('image_versions2', {}).get('candidates', [])
                if candidates:
                    # Sort by width (largest first)
                    candidates.sort(key=lambda x: x.get('width', 0), reverse=True)
                    image_url = candidates[0].get('url')
                    title = item.get('caption', {}).get('text', 'Instagram Image') if item.get('caption') else 'Instagram Image'
                    title = "".join(c for c in title if c.isalnum() or c in " _-").strip()[:100]
                    logger.info("Instagram Image Fallback: Found image URL!")
                    return {
                        'direct_url': image_url,
                        'title': title,
                        'ext': 'jpg',
                        'is_video': False,
                    }
    except Exception as e:
        logger.warning("Instagram GraphQL API failed: %s", e)

    # Fallback: Try OEmbed API (public posts only, no auth needed)
    try:
        oembed_url = f'https://www.instagram.com/api/v1/oembed/?url=https://www.instagram.com/p/{shortcode}/'
        logger.info("Instagram Image Fallback: Trying OEmbed %s", oembed_url)
        resp = http_requests.get(oembed_url, headers=headers, timeout=10)
        if resp.status_code == 200:
            data = resp.json()
            thumbnail = data.get('thumbnail_url')
            if thumbnail:
                title = data.get('title', 'Instagram Image')
                title = "".join(c for c in title if c.isalnum() or c in " _-").strip()[:100]
                logger.info("Instagram Image Fallback: Found thumbnail via OEmbed!")
                return {
                    'direct_url': thumbnail,
                    'title': title,
                    'ext': 'jpg',
                    'is_video': False,
                }
    except Exception as e:
        logger.warning("Instagram OEmbed API failed: %s", e)

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

    logger.info("Cookies received: %s", "YES" if video_request.cookies else "NO")
    cookie_file = _get_cookie_file(video_request.cookies)
    logger.info("Cookie file path: %s", cookie_file)

    ydl_opts = {
        "quiet": False,  # Enable output for debugging
        "verbose": True, # Enable verbose output
        "ignoreerrors": True,
        "noplaylist": "instagram.com" not in url and "tiktok.com" not in url, 
        "extract_flat": False,
        "skip_download": True,
        "nocheckcertificate": True, # Disable SSL checks to avoid handshake timeouts
        # Allow selecting 'none' video formats (images)
        "writethumbnail": True,
        "ignore_no_formats_error": True, # Key fix for Instagram images

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
            try:
                info = ydl.extract_info(url, download=False)
            except yt_dlp.utils.DownloadError:
                info = None

            logger.info("Extraction Result: %s", "None" if info is None else f"Found info with keys: {list(info.keys()) if info else 'None'}")

            if info is None:
                logger.warning("Extraction failed, retrying with distinct fallback options for Image...")
                # Create fresh options for fallback
                fallback_opts = ydl_opts.copy()
                fallback_opts.pop('format', None) # Remove format constraint
                fallback_opts['extract_flat'] = True # Get metadata only
                
                with yt_dlp.YoutubeDL(fallback_opts) as ydl_fallback:
                    try:
                        info = ydl_fallback.extract_info(url, download=False)
                    except Exception as e:
                        logger.error("Fallback extraction also failed: %s", e)
                        raise HTTPException(status_code=400, detail="Could not extract media (Video or Image).")


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

            # Debug: Log all possible URL sources
            logger.info("DEBUG url=%s", info.get("url"))
            logger.info("DEBUG thumbnail=%s", info.get("thumbnail"))
            logger.info("DEBUG thumbnails=%s", info.get("thumbnails"))
            logger.info("DEBUG formats count=%s", len(info.get("formats", [])))
            formats = info.get("formats", [])
            for i, f in enumerate(formats):
                logger.info("DEBUG format[%d]: url=%s vcodec=%s ext=%s", i, f.get("url", "")[:80] if f.get("url") else "None", f.get("vcodec"), f.get("ext"))

            # Get the best direct URL
            direct_url = info.get("url")
            http_headers = info.get("http_headers", {})

            # If no URL selected by yt-dlp, find it manually from formats
            if not direct_url:
                 if formats:
                     direct_url = formats[-1].get("url")
                     if formats[-1].get("http_headers"):
                         http_headers = formats[-1].get("http_headers")

            # Fallback: thumbnails list
            if not direct_url:
                thumbnails = info.get("thumbnails", [])
                if thumbnails:
                    direct_url = thumbnails[-1].get("url")
                    is_video = False

            # Fallback: thumbnail (singular key)
            if not direct_url:
                thumbnail = info.get("thumbnail")
                if thumbnail:
                    direct_url = thumbnail
                    is_video = False

            # Instagram image fallback: use direct API when yt-dlp fails
            if not direct_url and "instagram.com" in url:
                logger.info("Trying Instagram Image API fallback...")
                ig_result = _extract_instagram_image(url, cookie_file)
                if ig_result:
                    return {
                        "status": "success",
                        "title": ig_result['title'] or "Media",
                        "direct_url": ig_result['direct_url'],
                        "ext": ig_result['ext'],
                        "media_type": "image",
                        "headers": http_headers,
                    }

            if not direct_url:
                logger.error("No direct URL found. Full info dump: %s", {k: v for k, v in info.items() if k not in ('formats', 'http_headers', 'requested_subtitles')})
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