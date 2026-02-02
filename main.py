import os
from fastapi import FastAPI, HTTPException
from pydantic import BaseModel
import yt_dlp
from fastapi.middleware.cors import CORSMiddleware

app = FastAPI()

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_methods=["*"],
    allow_headers=["*"],
)

class VideoRequest(BaseModel):
    url: str


def get_best_format_url(info: dict) -> str | None:
    """
    Extract the best quality direct URL from yt-dlp info.
    Prioritizes formats with both video and audio combined.
    """
    formats = info.get('formats', [])
    if not formats:
        # If no formats list, try direct URL
        return info.get('url')
    
    # First, try to find a format with both video and audio
    best_combined = None
    best_combined_quality = -1
    
    for fmt in formats:
        has_video = fmt.get('vcodec') and fmt.get('vcodec') != 'none'
        has_audio = fmt.get('acodec') and fmt.get('acodec') != 'none'
        
        if has_video and has_audio:
            # Calculate quality score (higher is better)
            height = fmt.get('height', 0) or 0
            tbr = fmt.get('tbr', 0) or 0
            quality = height * 1000 + tbr
            
            if quality > best_combined_quality:
                best_combined_quality = quality
                best_combined = fmt
    
    if best_combined:
        return best_combined.get('url')
    
    # Fallback: get the best video-only format
    best_video = None
    best_video_quality = -1
    
    for fmt in formats:
        has_video = fmt.get('vcodec') and fmt.get('vcodec') != 'none'
        if has_video:
            height = fmt.get('height', 0) or 0
            tbr = fmt.get('tbr', 0) or 0
            quality = height * 1000 + tbr
            
            if quality > best_video_quality:
                best_video_quality = quality
                best_video = fmt
    
    if best_video:
        return best_video.get('url')
    
    # Ultimate fallback: return the 'url' field from info
    return info.get('url')


def get_thumbnail_url(info: dict) -> str | None:
    """Extract the best thumbnail URL from info."""
    # Direct thumbnail field
    if info.get('thumbnail'):
        return info.get('thumbnail')
    
    # Try thumbnails list (pick the last one, usually highest quality)
    thumbnails = info.get('thumbnails', [])
    if thumbnails:
        return thumbnails[-1].get('url')
    
    return None


def detect_source(url: str) -> str:
    """Detect the source platform from URL."""
    url_lower = url.lower()
    if 'instagram' in url_lower:
        return 'instagram'
    elif 'tiktok' in url_lower:
        return 'tiktok'
    elif 'facebook' in url_lower or 'fb.watch' in url_lower:
        return 'facebook'
    elif 'youtube' in url_lower or 'youtu.be' in url_lower:
        return 'youtube'
    elif 'twitter' in url_lower or 'x.com' in url_lower:
        return 'twitter'
    else:
        return 'unknown'


@app.post("/extract")
def extract_info(request: VideoRequest):
    url = request.url.strip()

    # Cookie file setup
    cookie_file = "cookies.txt"
    use_cookies = os.path.exists(cookie_file)

    # yt-dlp options - CRUCIAL: download=False, we only extract info
    ydl_opts = {
        'quiet': True,
        'ignoreerrors': True,
        'noplaylist': True,
        'extract_flat': False,
        'skip_download': True,  # Ensure no download happens
        'user_agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
        # Format selection: prefer best combined (video+audio), fallback to best available
        'format': 'best[ext=mp4]/best/bestvideo+bestaudio/bestvideo/best',
    }

    if use_cookies:
        ydl_opts['cookiefile'] = cookie_file

    try:
        print(f"⏳ Extracting info for: {url}")
        
        with yt_dlp.YoutubeDL(ydl_opts) as ydl:
            # Extract info WITHOUT downloading
            info = ydl.extract_info(url, download=False)
            
            if info is None:
                raise HTTPException(
                    status_code=400, 
                    detail="Could not extract info. The URL may be invalid, private, or require login."
                )

            # Handle playlists/carousels - pick the first entry
            if 'entries' in info:
                print("📸 Detected Carousel/Playlist, picking first entry...")
                try:
                    entries = list(info['entries'])
                    if not entries:
                        raise HTTPException(status_code=400, detail="Empty playlist/carousel.")
                    info = entries[0]
                    if info is None:
                        raise HTTPException(status_code=400, detail="First entry in playlist is empty.")
                except (IndexError, TypeError):
                    raise HTTPException(status_code=400, detail="Could not extract from playlist/carousel.")

            # Determine media type
            is_video = True
            if info.get('vcodec') == 'none' or info.get('ext') in ['jpg', 'jpeg', 'png', 'webp', 'heic']:
                is_video = False

            # Get the direct URL
            direct_url = get_best_format_url(info)
            
            if not direct_url:
                raise HTTPException(
                    status_code=400, 
                    detail="Could not extract direct download URL. The media may be protected."
                )

            # Get metadata
            title = info.get('title', 'Untitled Media')
            if title:
                title = title[:100]  # Limit title length
            
            thumbnail = get_thumbnail_url(info)
            source = detect_source(url)
            ext = info.get('ext', 'mp4')
            media_type = "video" if is_video else "image"
            
            # Duration in seconds (if available)
            duration = info.get('duration')
            
            # File size (if available, in bytes)
            filesize = info.get('filesize') or info.get('filesize_approx')

            print(f"✅ Extracted successfully: {title}")
            print(f"   Direct URL: {direct_url[:80]}...")
            
            return {
                "status": "success",
                "direct_url": direct_url,
                "title": title,
                "thumbnail": thumbnail,
                "source": source,
                "ext": ext if ext and ext != 'none' else 'mp4',
                "media_type": media_type,
                "duration": duration,
                "filesize": filesize,
            }

    except HTTPException as he:
        raise he
    except Exception as e:
        print(f"🔥 Error: {str(e)}")
        raise HTTPException(status_code=400, detail=str(e))


@app.get("/health")
def health_check():
    """Health check endpoint."""
    return {"status": "ok", "message": "Server is running"}


if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="0.0.0.0", port=8000)