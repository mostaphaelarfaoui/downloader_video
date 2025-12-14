import os
import time
import uuid
import socket
from fastapi import FastAPI, HTTPException, Request
from fastapi.staticfiles import StaticFiles
from pydantic import BaseModel
import yt_dlp
from fastapi.middleware.cors import CORSMiddleware

app = FastAPI()

# 1. Setup Downloads Folder
DOWNLOAD_DIR = "downloads"
if not os.path.exists(DOWNLOAD_DIR):
    os.makedirs(DOWNLOAD_DIR)

# Mount the folder to serve files via HTTP
app.mount("/downloads", StaticFiles(directory=DOWNLOAD_DIR), name="downloads")

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_methods=["*"],
    allow_headers=["*"],
)

class VideoRequest(BaseModel):
    url: str

def get_local_ip():
    """Try to detect the machine's local IP address"""
    try:
        s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        s.connect(("8.8.8.8", 80))
        ip = s.getsockname()[0]
        s.close()
        return ip
    except:
        return "127.0.0.1"

@app.post("/extract")
def extract_info(request: VideoRequest, req: Request):
    # Generate a unique filename
    unique_name = str(uuid.uuid4())
    
    # Configure yt-dlp to DOWNLOAD the file locally
    ydl_opts = {
        'format': 'best[ext=mp4]/best', # Force MP4
        'outtmpl': f'{DOWNLOAD_DIR}/{unique_name}.%(ext)s',
        'quiet': True,
        'no_warnings': True,
        'restrictfilenames': True,
    }

    try:
        with yt_dlp.YoutubeDL(ydl_opts) as ydl:
            # 1. Extract info and Download
            info = ydl.extract_info(request.url, download=True)
            
            # 2. Get the filename that was saved
            # yt-dlp might change extension, so we verify
            filename = ydl.prepare_filename(info)
            basename = os.path.basename(filename)
            ext = info.get('ext', 'mp4')
            title = info.get('title', 'video')

            # 3. Construct the Local URL
            # We use the request.base_url to get the current server IP/Port dynamically
            # Or fallback to detected IP if needed.
            host_url = str(req.base_url).rstrip('/')
            local_download_url = f"{host_url}/downloads/{basename}"

            print(f"File downloaded to: {filename}")
            print(f"Serving at: {local_download_url}")

            return {
                "status": "success",
                "title": title,
                "thumbnail": info.get('thumbnail'),
                "download_url": local_download_url, # Now pointing to OUR server
                "ext": ext,
                "headers": {} # No special headers needed for local download
            }

    except Exception as e:
        print(f"Error: {str(e)}")
        raise HTTPException(status_code=400, detail=str(e))

if __name__ == "__main__":
    import uvicorn
    # Listen on 0.0.0.0 to allow mobile connection
    uvicorn.run(app, host="0.0.0.0", port=8000)
