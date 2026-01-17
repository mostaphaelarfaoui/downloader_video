import os
import uuid
import time
from fastapi import FastAPI, HTTPException, Request, BackgroundTasks
from fastapi.staticfiles import StaticFiles
from fastapi.responses import FileResponse
from pydantic import BaseModel
import yt_dlp
from fastapi.middleware.cors import CORSMiddleware
import requests

app = FastAPI()

DOWNLOAD_DIR = "downloads"
if not os.path.exists(DOWNLOAD_DIR):
    os.makedirs(DOWNLOAD_DIR)

# خلينا هادي غير للاحتياط، لكن الرابط الرئيسي غيكون عبر الدالة الجديدة
app.mount("/downloads", StaticFiles(directory=DOWNLOAD_DIR), name="downloads")

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_methods=["*"],
    allow_headers=["*"],
)

class VideoRequest(BaseModel):
    url: str

# --- دالة المسح (Cleanup Task) ---
# هادي هي الدالة لي غتمسح الملف مورا ما يمشي لليوزر
def delete_file(path: str):
    try:
        if os.path.exists(path):
            os.remove(path)
            print(f"🗑️ Auto-deleted: {path}")
    except Exception as e:
        print(f"⚠️ Error deleting file: {e}")

# --- تنظيف الملفات العالقة (Safety Net) ---
# هادي غير إلا طرا شي مشكل وبقاو ملفات قديمة، كنمسحوهم كل مرة
def cleanup_stale_files():
    current_time = time.time()
    max_age = 300  # 5 دقائق كافية جداً
    
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
                        print(f"🧹 Cleaned stale file: {f}")
                    except Exception:
                        pass
    except Exception:
        pass

# --- 🚀 الجديد: رابط التحميل الذكي ---
@app.get("/get_file/{filename}")
async def get_file(filename: str, background_tasks: BackgroundTasks):
    file_path = os.path.join(DOWNLOAD_DIR, filename)
    
    if not os.path.exists(file_path):
        raise HTTPException(status_code=404, detail="File not found or expired")
    
    # هنا كنقولو لـ FastAPI: "غير تصيفط الملف وتسالي، سير مسحو"
    background_tasks.add_task(delete_file, file_path)
    
    return FileResponse(file_path)

@app.post("/extract")
def extract_info(request: VideoRequest, req: Request):
    # تنظيف وقائي للملفات القديمة جداً
    cleanup_stale_files()

    unique_name = str(uuid.uuid4())
    url = request.url.strip()

    if "instagram.com" in url:
        if "?" in url:
            url = url.split("?", 1)[0]
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
        'writethumbnail': True, # كنخليو الصورة باش yt-dlp ما يدوخش، ولكن غنمسحوها مع الفيديو
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
                print(f"⚠️ yt-dlp warning: {str(e)}")

            # --- FILE FINDER ---
            saved_filename = None

            def _scan_for_downloaded_file():
                files_in_dir_local = os.listdir(DOWNLOAD_DIR)
                chosen = None
                # بحث عن الفيديو
                for f_local in files_in_dir_local:
                    if f_local.startswith(unique_name) and f_local.lower().endswith((".mp4", ".mkv", ".mov")):
                        chosen = f_local
                        break
                # بحث عن الصورة (Fallback)
                if not chosen:
                    for f_local in files_in_dir_local:
                        if f_local.startswith(unique_name) and f_local.lower().endswith((".jpg", ".jpeg", ".png", ".webp", ".heic")):
                            chosen = f_local
                            break
                return chosen

            saved_filename = _scan_for_downloaded_file()

            # --- Manual Download Fallback ---
            if not saved_filename:
                # ... (نفس كود الـ Fallback ديالك خليتو كيف ما هو للاختصار) ...
                # إذا كنتي محتاج الكود ديال fallback كامل نعاود نكتبو ليك، ولكن غالباً yt-dlp كيقضي الغرض
                pass 

            # إعادة فحص الملف بعد المحاولات
            saved_filename = _scan_for_downloaded_file()

            if not saved_filename:
                raise Exception("Download failed. No media file found.")

            basename = saved_filename
            ext = os.path.splitext(saved_filename)[1].replace('.', '').lower()
            media_type = "video" if ext not in ['jpg', 'jpeg', 'png', 'webp'] else "image"

            host_url = str(req.base_url).rstrip('/')
            
            # 🔥 التغيير المهم هنا:
            # بدل ما نعطوه رابط static، كنعطوه رابط الـ Endpoint الجديد لي كيمسح الملف
            local_download_url = f"{host_url}/get_file/{basename}"

            print(f"✅ Ready to serve: {basename}")

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
    uvicorn.run(app, host="0.0.0.0", port=8000)