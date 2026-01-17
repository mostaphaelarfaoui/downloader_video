import os
import uuid
import time
import re  # مكتبة للتعامل مع النصوص
from fastapi import FastAPI, HTTPException, Request, BackgroundTasks
from fastapi.responses import FileResponse
from pydantic import BaseModel
import yt_dlp
import instaloader  # المكتبة الجديدة لانستغرام
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

# --- إعداد Instaloader ---
L = instaloader.Instaloader()

# --- دالة مساعدة لانستغرام ---
def get_instagram_direct_link(url: str):
    try:
        # استخراج الكود القصير (Shortcode) من الرابط
        shortcode_match = re.search(r'/(p|reel|tv)/([^/?#&]+)', url)
        if not shortcode_match:
            return None 

        shortcode = shortcode_match.group(2)
        
        # جلب معلومات البوست
        post = instaloader.Post.from_shortcode(L.context, shortcode)
        
        caption = post.caption if post.caption else "Instagram Media"
        # تقليص العنوان إذا كان طويلاً
        title = (caption[:50] + '..') if len(caption) > 50 else caption

        if post.is_video:
            return {
                "direct_url": post.video_url,
                "title": title,
                "is_video": True,
                "ext": "mp4"
            }
        else:
            return {
                "direct_url": post.url, # هذا رابط الصورة المباشر
                "title": title,
                "is_video": False,
                "ext": "jpg"
            }
    except Exception as e:
        print(f"⚠️ Instaloader error: {e}")
        return None

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

    # ==========================================
    # 1. محاولة خاصة بـ Instagram (للصور والفيديو)
    # ==========================================
    if "instagram.com" in url:
        print("📸 Detected Instagram URL, checking type...")
        insta_data = get_instagram_direct_link(url)
        
        # إذا نجحنا في جلب الرابط المباشر من انستغرام
        if insta_data:
            print("✅ Instaloader success!")
            return {
                "status": "success",
                "title": insta_data["title"],
                "download_url": insta_data["direct_url"], # رابط CDN مباشر
                "ext": insta_data["ext"],
                "media_type": "video" if insta_data["is_video"] else "image",
            }
        else:
            print("⚠️ Instaloader failed, falling back to yt-dlp...")
    
    # ==========================================
    # 2. الطريقة العادية (yt-dlp) لباقي المواقع
    # ==========================================
    
    unique_name = str(uuid.uuid4())
    
    # Check Cookies
    cookie_file = "cookies.txt"
    use_cookies = os.path.exists(cookie_file)

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
            print(f"⏳ Downloading with yt-dlp: {url}")
            ydl.extract_info(url, download=True)

            # البحث عن الملف المحمل
            saved_filename = None
            files_in_dir_local = os.listdir(DOWNLOAD_DIR)
            
            # بحث عن فيديو أولاً
            for f_local in files_in_dir_local:
                if f_local.startswith(unique_name) and f_local.lower().endswith((".mp4", ".mkv", ".mov")):
                    saved_filename = f_local
                    break
            
            # بحث عن صورة (احتياط)
            if not saved_filename:
                for f_local in files_in_dir_local:
                    if f_local.startswith(unique_name) and f_local.lower().endswith((".jpg", ".jpeg", ".png", ".webp")):
                        saved_filename = f_local
                        break

            if not saved_filename:
                raise Exception("Download failed. No media file found.")

            basename = saved_filename
            ext = os.path.splitext(saved_filename)[1].replace('.', '').lower()
            media_type = "video" if ext not in ['jpg', 'jpeg', 'png', 'webp'] else "image"

            host_url = str(req.base_url).rstrip('/')
            local_download_url = f"{host_url}/get_file/{basename}"

            return {
                "status": "success",
                "title": "Media Download",
                "download_url": local_download_url, # رابط من السيرفر ديالنا
                "ext": ext,
                "media_type": media_type,
            }

    except Exception as e:
        print(f"🔥 Error: {str(e)}")
        raise HTTPException(status_code=400, detail=str(e))

if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="0.0.0.0", port=8000)