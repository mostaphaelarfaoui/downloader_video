import os
import uuid
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

@app.post("/extract")
def extract_info(request: VideoRequest, req: Request):
    unique_name = str(uuid.uuid4())
    
    # Check Cookies
    cookie_file = "cookies.txt"
    use_cookies = os.path.exists(cookie_file)
    
    if use_cookies:
        print("🍪 Cookies.txt FOUND! Using for authentication.")
    else:
        print("⚠️ No cookies.txt found. Instagram might block this.")

    ydl_opts = {
        'outtmpl': f'{DOWNLOAD_DIR}/{unique_name}.%(ext)s',
        'format': 'bestvideo+bestaudio/best',  # Force best video
        'quiet': True,
        'no_warnings': True,
        'writethumbnail': True,  # We keep this, but ignore the file if video exists
        'ignoreerrors': True,
    }
    
    if use_cookies:
        ydl_opts['cookiefile'] = cookie_file

    try:
        with yt_dlp.YoutubeDL(ydl_opts) as ydl:
            print(f"⏳ Downloading: {request.url}")
            info = ydl.extract_info(request.url, download=True)
            
            # --- INTELLIGENT FILE SEARCH ---
            saved_filename = None
            files_in_dir = os.listdir(DOWNLOAD_DIR)
            
            # PRIORITY 1: Look for VIDEO files first
            for f in files_in_dir:
                if f.startswith(unique_name) and f.lower().endswith((".mp4", ".mkv", ".mov", ".avi")):
                    saved_filename = f
                    break
            
            # PRIORITY 2: If no video, look for IMAGE files (Fallback)
            if not saved_filename:
                for f in files_in_dir:
                    if f.startswith(unique_name) and f.lower().endswith((".jpg", ".jpeg", ".png", ".webp")):
                        saved_filename = f
                        break
            
            if not saved_filename:
                print(f"❌ Error: UUID {unique_name} not found.")
                print(f"📂 Dir content: {files_in_dir}")
                raise Exception("Download failed or file not found.")

            basename = saved_filename
            ext = os.path.splitext(saved_filename)[1].replace('.', '').lower()
            title = info.get('title', 'media') if info else 'media'

            media_type = "video"
            if ext in ['jpg', 'jpeg', 'png', 'webp', 'gif']:
                media_type = "image"

            host_url = str(req.base_url).rstrip('/')
            local_download_url = f"{host_url}/downloads/{basename}"

            print(f"✅ Success! Served: {basename} ({media_type})")

            return {
                "status": "success",
                "title": title,
                "download_url": local_download_url,
                "ext": ext,
                "media_type": media_type,
            }

    except Exception as e:
        print(f"🔥 Server Error: {str(e)}")
        raise HTTPException(status_code=400, detail=str(e))

if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="0.0.0.0", port=8000)