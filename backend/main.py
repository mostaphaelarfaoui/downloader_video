import os
import uuid
import time
from fastapi import FastAPI, HTTPException, Request
from fastapi.staticfiles import StaticFiles
from pydantic import BaseModel
import yt_dlp
from fastapi.middleware.cors import CORSMiddleware
import requests

app = FastAPI()

DOWNLOAD_DIR = "downloads"
if not os.path.exists(DOWNLOAD_DIR):
    os.makedirs(DOWNLOAD_DIR)

app.mount("/downloads", StaticFiles(directory=DOWNLOAD_DIR), name="downloads")

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_methods=["*"],
    allow_headers=["*"],
)

class VideoRequest(BaseModel):
    url: str

# --- دالة التنظيف (The Cleaner) ---
# هذه الدالة تمسح الملفات القديمة (أكثر من 10 دقائق) لتوفير المساحة في Render
def cleanup_old_files():
    """Delete files older than 10 minutes to save space on Render"""
    current_time = time.time()
    # 10 minutes = 600 seconds
    max_age = 600 
    
    try:
        if not os.path.exists(DOWNLOAD_DIR):
            return

        files = os.listdir(DOWNLOAD_DIR)
        for f in files:
            file_path = os.path.join(DOWNLOAD_DIR, f)
            # Check file age
            if os.path.exists(file_path):
                file_age = current_time - os.path.getmtime(file_path)
                if file_age > max_age:
                    try:
                        os.remove(file_path)
                        print(f"🧹 Cleaned up old file: {f}")
                    except Exception as e:
                        print(f"⚠️ Error deleting {f}: {e}")
    except Exception as e:
        print(f"⚠️ Cleanup error: {e}")

@app.post("/extract")
def extract_info(request: VideoRequest, req: Request):
    # 1. Start Cleanup BEFORE downloading new file
    cleanup_old_files()

    unique_name = str(uuid.uuid4())

    # Normalize Instagram URLs: strip tracking/query params like ?utm_source=...
    url = request.url.strip()

    if "instagram.com" in url:
        # Remove query parameters
        if "?" in url:
            url = url.split("?", 1)[0]

        # Basic generic-home check AFTER normalization
        if len(url.split('/')) < 4:
            raise HTTPException(status_code=400, detail="Generic URL. Please open a specific post first.")

    # Check Cookies
    cookie_file = "cookies.txt"
    use_cookies = os.path.exists(cookie_file)
    print(f"🍪 Cookies found: {use_cookies}")

    ydl_opts = {
        'outtmpl': f'{DOWNLOAD_DIR}/{unique_name}.%(ext)s',
        'format': 'best',
        'quiet': True,
        'ignoreerrors': True,
        'writethumbnail': True,
        'noplaylist': True,
    }

    if use_cookies:
        ydl_opts['cookiefile'] = cookie_file

    try:
        with yt_dlp.YoutubeDL(ydl_opts) as ydl:
            print(f"⏳ Downloading: {url}")
            try:
                ydl.extract_info(url, download=True)
            except Exception as e:
                # CRITICAL: Do not crash for photo posts (e.g. "No video formats found")
                print(f"⚠️ yt-dlp warning (ignored): {str(e)}")

            # --- FILE FINDER ---
            saved_filename = None

            def _scan_for_downloaded_file() -> tuple[str | None, list[str]]:
                """Scan DOWNLOAD_DIR for files that belong to this request UUID.

                Returns (saved_filename, files_in_dir).
                """
                files_in_dir_local = os.listdir(DOWNLOAD_DIR)
                chosen: str | None = None

                # Pass 1: Look for VIDEO
                for f_local in files_in_dir_local:
                    if f_local.startswith(unique_name) and f_local.lower().endswith((".mp4", ".mkv", ".mov")):
                        chosen = f_local
                        break

                # Pass 2: Look for IMAGE (Fallback)
                if not chosen:
                    for f_local in files_in_dir_local:
                        if f_local.startswith(unique_name) and f_local.lower().endswith((".jpg", ".jpeg", ".png", ".webp", ".heic")):
                            chosen = f_local
                            break

                return chosen, files_in_dir_local

            saved_filename, files_in_dir = _scan_for_downloaded_file()

            # --- FALLBACK: manual download using info dict if yt-dlp didn't write any file ---
            if not saved_filename:
                try:
                    info = ydl.extract_info(url, download=False)
                except Exception as e:
                    print(f"⚠️ yt-dlp metadata fetch failed: {e}")
                    info = None

                def _pick_entry(info_obj):
                    if not info_obj:
                        return None
                    if isinstance(info_obj, dict) and info_obj.get("entries"):
                        # Playlist-like, pick first entry
                        entries = info_obj["entries"]
                        return entries[0] if entries else None
                    return info_obj

                entry = _pick_entry(info)
                media_url = None
                ext = None

                if isinstance(entry, dict):
                    # Try direct url first (often image or single file)
                    media_url = entry.get("url")
                    ext = entry.get("ext")

                    # If formats exist, prefer best format url
                    formats = entry.get("formats") or []
                    if formats:
                        best = formats[-1]
                        media_url = best.get("url") or media_url
                        ext = best.get("ext") or ext

                    # If still no media_url, try thumbnail for images
                    if not media_url:
                        media_url = entry.get("thumbnail")
                        if media_url and not ext:
                            ext = "jpg"

                if media_url:
                    try:
                        print(f"⬇️ Fallback direct download: {media_url}")
                        resp = requests.get(media_url, stream=True, timeout=30)
                        resp.raise_for_status()

                        if not ext:
                            # Guess a basic extension
                            content_type = resp.headers.get("Content-Type", "")
                            if "image" in content_type:
                                ext = "jpg"
                            elif "video" in content_type:
                                ext = "mp4"
                            else:
                                ext = "bin"

                        target_path = os.path.join(DOWNLOAD_DIR, f"{unique_name}.{ext}")
                        with open(target_path, "wb") as f_out:
                            for chunk in resp.iter_content(chunk_size=8192):
                                if chunk:
                                    f_out.write(chunk)

                        # Re-scan after manual download
                        saved_filename, files_in_dir = _scan_for_downloaded_file()
                    except Exception as e:
                        print(f"⚠️ Fallback direct download failed: {e}")

            if not saved_filename:
                print(f"❌ Error: No file found for UUID {unique_name}")
                print(f"📂 Dir content: {files_in_dir}")
                raise Exception("Download failed. No media file found (Video or Image).")

            basename = saved_filename
            ext = os.path.splitext(saved_filename)[1].replace('.', '').lower()

            media_type = "video"
            if ext in ['jpg', 'jpeg', 'png', 'webp', 'gif', 'heic']:
                media_type = "image"

            host_url = str(req.base_url).rstrip('/')
            local_download_url = f"{host_url}/downloads/{basename}"

            print(f"✅ Served: {basename} ({media_type})")

            return {
                "status": "success",
                "title": "Media Download",
                "download_url": local_download_url,
                "ext": ext,
                "media_type": media_type,
            }

    except Exception as e:
        print(f"🔥 Error: {str(e)}")
        raise HTTPException(status_code=400, detail=str(e))

if __name__ == "__main__":
    import uvicorn
    # Important: Use port 8000 locally, but Render will override it via env var
    uvicorn.run(app, host="0.0.0.0", port=8000)