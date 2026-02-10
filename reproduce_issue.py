import yt_dlp
import logging

# Configure logging to see what's happening
logging.basicConfig(level=logging.DEBUG)
logger = logging.getLogger("test")

url = "https://vt.tiktok.com/ZSm8MnJ"

ydl_opts = {
    "quiet": False, # Enable output to see errors
    "ignoreerrors": True,
    "noplaylist": True,
    "extract_flat": False,
    "skip_download": True,
    "user_agent": (
        "Mozilla/5.0 (Windows NT 10.0; Win64; x64) "
        "AppleWebKit/537.36 (KHTML, like Gecko) "
        "Chrome/120.0.0.0 Safari/537.36"
    ),
}

print(f"Testing URL: {url}")

try:
    with yt_dlp.YoutubeDL(ydl_opts) as ydl:
        info = ydl.extract_info(url, download=False)
        
        if info is None:
            print("Info is None")
        else:
            print("Success!")
            print(f"Title: {info.get('title')}")
            print(f"URL: {info.get('url')}")
            
            # Check for formats
            formats = info.get("formats", [])
            print(f"Num formats: {len(formats)}")
            
except Exception as e:
    print(f"Caught exception: {e}")
    # Print full traceback
    import traceback
    traceback.print_exc()
