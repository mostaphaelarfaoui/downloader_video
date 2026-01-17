import os
import uuid
import time
import requests
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

# --- دالة تحميل الصور يدوياً ---
def download_image_manual(url, filename):
    headers = {
        "User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/91.0.4472.124 Safari/537.36"
    }
    try:
        response = requests.get(url, headers=headers, stream=True, timeout=10)
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

    # خيارات yt-dlp محسنة لتفادي الحظر
    ydl_opts = {
        'outtmpl': f'{DOWNLOAD_DIR}/{unique_name}.%(ext)s',
        'quiet': True,
        'ignoreerrors': True, # ضروري باش ما يوقفش إلا فشل جزء
        'noplaylist': True,   # كنحاولو نتفاداو البلايليست الطويلة
        'extract_flat': False,
        'user_agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/91.0.4472.124 Safari/537.36',
    }

    if use_cookies:
        ydl_opts['cookiefile'] = cookie_file

    try:
        print(f"⏳ Analyzing URL: {url}")
        
        with yt_dlp.YoutubeDL(ydl_opts) as ydl:
            # 1. استخراج المعلومات
            info = ydl.extract_info(url, download=False)
            
            # 🔥 الإصلاح الأول: التحقق من أن info ليس فارغاً
            if info is None:
                raise HTTPException(status_code=400, detail="Instagram blocked the request or URL is invalid (Login Required).")

            # 🔥 الإصلاح الثاني: التعامل مع ألبومات الصور (Carousel)
            # إلا كان الرابط فيه بزاف التصاور، yt-dlp كيرد 'entries'
            if 'entries' in info:
                print("📸 Detected Carousel/Playlist, picking first entry...")
                # خود أول وحدة فالألبوم
                try:
                    info = list(info['entries'])[0] 
                except IndexError:
                     raise HTTPException(status_code=400, detail="Empty playlist/carousel.")

            # 2. تحديد النوع (فيديو ولا صورة)
            is_video = True
            # yt-dlp كيعطي vcodec='none' للصور، أو ext كيكون jpg/png
            if info.get('vcodec') == 'none' or info.get('ext') in ['jpg', 'jpeg', 'png', 'webp', 'heic']:
                is_video = False
            
            # --- الحالة A: فيديو ---
            if is_video:
                print("🎥 Type: Video - Downloading...")
                # نعاودو التحميل لهاد الرابط المحدد فقط
                ydl.download([info.get('webpage_url', url)])
                
                saved_filename = None
                for f in os.listdir(DOWNLOAD_DIR):
                    if f.startswith(unique_name) and f.lower().endswith((".mp4", ".mkv", ".mov", ".webm")):
                        saved_filename = f
                        break
            
            # --- الحالة B: صورة ---
            else:
                print("🖼️ Type: Image - Downloading manually...")
                image_url = info.get('url')
                if not image_url:
                     # محاولة استخراج رابط بديل إذا كان الأول فارغ
                     image_url = info.get('thumbnails', [{}])[-1].get('url')

                if not image_url:
                    raise Exception("Could not find image URL")

                ext = info.get('ext', 'jpg')
                if ext == 'none': ext = 'jpg'
                
                target_file = f"{DOWNLOAD_DIR}/{unique_name}.{ext}"
                success = download_image_manual(image_url, target_file)
                
                if success:
                    saved_filename = f"{unique_name}.{ext}"
                else:
                    raise Exception("Failed to download image file via requests")

            # التحقق النهائي
            if not saved_filename:
                raise Exception("File not found on server after processing.")

            basename = saved_filename
            final_ext = os.path.splitext(saved_filename)[1].replace('.', '').lower()
            media_type = "video" if is_video else "image"
            
            host_url = str(req.base_url).rstrip('/')
            local_download_url = f"{host_url}/get_file/{basename}"

            return {
                "status": "success",
                "title": info.get('title', 'Instagram Media')[:100],
                "download_url": local_download_url,
                "ext": final_ext,
                "media_type": media_type,
            }

    except HTTPException as he:
        raise he
    except Exception as e:
        print(f"🔥 Error: {str(e)}")
        # نرسلو الخطأ للتطبيق باش يبان ليك
        raise HTTPException(status_code=400, detail=str(e))

if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="0.0.0.0", port=8000)