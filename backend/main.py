import os
import uuid
import time
from fastapi import FastAPI, HTTPException, Request
from fastapi.staticfiles import StaticFiles
from pydantic import BaseModel
import yt_dlp
from fastapi.middleware.cors import CORSMiddleware

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

    # 2. Block Generic Home URLs
    if "instagram.com" in request.url and len(request.url.split('/')) < 4:
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
            print(f"⏳ Downloading: {request.url}")
            try:
                ydl.extract_info(request.url, download=True)
            except Exception as e:
                # CRITICAL: Do not crash for photo posts (e.g. "No video formats found")
                print(f"⚠️ yt-dlp warning (ignored): {str(e)}")

            # --- FILE FINDER ---
            saved_filename = None
            files_in_dir = os.listdir(DOWNLOAD_DIR)

            # Pass 1: Look for VIDEO
            for f in files_in_dir:
                if f.startswith(unique_name) and f.lower().endswith(('.mp4', '.mkv', '.mov')):
                    saved_filename = f
                    break

            # Pass 2: Look for IMAGE (Fallback)
            if not saved_filename:
                for f in files_in_dir:
                    if f.startswith(unique_name) and f.lower().endswith(('.jpg', '.jpeg', '.png', '.webp', '.heic')):
                        saved_filename = f
                        break

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