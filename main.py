import os
import uuid
import time
import requests # ضروري باش نحملو الصور يدوياً
from fastapi import FastAPI, HTTPException, Request, BackgroundTasks
from fastapi.responses import FileResponse
from pydantic import BaseModel
import yt_dlp
from fastapi.middleware.cors import CORSMiddleware

app = FastAPI()

DOWNLOAD_DIR = "downloads"
if not os.path.exists(DOWNLOAD_DIR):
    os.makedirs(DOWNLOAD_DIR)

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_methods=["*"],
    allow_headers=["*"],
)

class VideoRequest(BaseModel):
    url: str

# --- دوال التنظيف ---
def delete_file(path: str):
    try:
        if os.path.exists(path):
            os.remove(path)
            print(f"🗑️ Auto-deleted: {path}")
    except Exception as e:
        print(f"⚠️ Error deleting file: {e}")

def cleanup_stale_files():
    current_time = time.time()
    max_age = 300
    try:
        if not os.path.exists(DOWNLOAD_DIR):
            return
        files = os.listdir(DOWNLOAD_DIR)
        for f in files:
            file_path = os.path.join(DOWNLOAD_DIR, f)
            if os.path.exists(file_path):
                file_age = current_time - os.path.getmtime(file_path)
                if file_age > max_age:
                    try:
                        os.remove(file_path)
                    except Exception:
                        pass
    except Exception:
        pass

# --- دالة مساعدة لتحميل الصور يدوياً ---
def download_image_manual(url, filename, cookie_file=None):
    headers = {
        "User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/91.0.4472.124 Safari/537.36"
    }
    # إلا كان عندنا كوكيز، نستعملوهم باش ما نتبلوكاوش
    cookies = {}
    if cookie_file and os.path.exists(cookie_file):
        # قراءة بسيطة للكوكيز (Netscape format is complex, but basic requests might work without full parsing if URL is CDN)
        # غالباً روابط الصور فـ انستغرام (CDN) كتكون عامة بمجرد استخراجها، يعني ما كتحتاجش كوكيز للتحميل، غير للاستخراج
        pass 
        
    try:
        response = requests.get(url, headers=headers, stream=True)
        if response.status_code == 200:
            with open(filename, 'wb') as f:
                for chunk in response.iter_content(1024):
                    f.write(chunk)
            return True
    except Exception as e:
        print(f"⚠️ Image download failed: {e}")
    return False

# --- الروابط (Endpoints) ---

@app.get("/get_file/{filename}")
async def get_file(filename: str, background_tasks: BackgroundTasks):
    file_path = os.path.join(DOWNLOAD_DIR, filename)
    if not os.path.exists(file_path):
        raise HTTPException(status_code=404, detail="File not found or expired")
    background_tasks.add_task(delete_file, file_path)
    return FileResponse(file_path)

@app.post("/extract")
def extract_info(request: VideoRequest, req: Request):
    cleanup_stale_files()
    url = request.url.strip()
    unique_name = str(uuid.uuid4())

    # إعداد الكوكيز
    cookie_file = "cookies.txt"
    use_cookies = os.path.exists(cookie_file)

    ydl_opts = {
        'outtmpl': f'{DOWNLOAD_DIR}/{unique_name}.%(ext)s',
        'quiet': True,
        'ignoreerrors': True,
        'noplaylist': True,
        'cookiefile': cookie_file if use_cookies else None,
    }

    try:
        print(f"⏳ Analyzing URL: {url}")
        
        # 1. نستخرجو المعلومات بلا تحميل (Simulation)
        with yt_dlp.YoutubeDL(ydl_opts) as ydl:
            info = ydl.extract_info(url, download=False)
            
            if not info:
                raise Exception("Failed to extract info")

            # التحقق واش "ألبوم" صور (Sidecar)
            if 'entries' in info:
                # ناخدو غير أول وحدة فحالياً
                info = info['entries'][0]

            # 2. تحديد النوع: واش فيديو ولا تصويرة؟
            # yt-dlp كيعطي 'vcodec': 'none' للصور
            is_video = True
            if info.get('vcodec') == 'none' or info.get('ext') in ['jpg', 'jpeg', 'png', 'webp']:
                is_video = False
            
            # --- 🅰️ حالة الفيديو ---
            if is_video:
                print("🎥 Type: Video - Using yt-dlp to download")
                ydl.download([url])
                
                # البحث عن الفيديو المحمل
                saved_filename = None
                for f in os.listdir(DOWNLOAD_DIR):
                    if f.startswith(unique_name) and f.lower().endswith((".mp4", ".mkv", ".mov", ".webm")):
                        saved_filename = f
                        break
            
            # --- 🅱️ حالة الصورة ---
            else:
                print("🖼️ Type: Image - Downloading manually")
                image_url = info.get('url') # yt-dlp جاب لينا الرابط المباشر
                ext = info.get('ext', 'jpg')
                if ext == 'none': ext = 'jpg'
                
                target_file = f"{DOWNLOAD_DIR}/{unique_name}.{ext}"
                
                # نحملوها بـ requests
                success = download_image_manual(image_url, target_file)
                
                if success:
                    saved_filename = f"{unique_name}.{ext}"
                else:
                    raise Exception("Failed to download image file")

            if not saved_filename:
                raise Exception("File not found after processing.")

            # تجهيز الرابط للرد
            basename = saved_filename
            final_ext = os.path.splitext(saved_filename)[1].replace('.', '').lower()
            media_type = "video" if is_video else "image"
            
            host_url = str(req.base_url).rstrip('/')
            local_download_url = f"{host_url}/get_file/{basename}"

            return {
                "status": "success",
                "title": info.get('title', 'Instagram Media'),
                "download_url": local_download_url,
                "ext": final_ext,
                "media_type": media_type,
            }

    except Exception as e:
        print(f"🔥 Error: {str(e)}")
        raise HTTPException(status_code=400, detail=str(e))

if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="0.0.0.0", port=8000)