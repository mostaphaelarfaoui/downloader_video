@echo off
echo ===================================================
echo   Starting Local Server on LAN (0.0.0.0:8000)
echo ===================================================
echo.
echo [1] Find your IPv4 Address below (look for 192.168.x.x):
ipconfig | findstr "IPv4"
echo.
echo [2] Update frontend/lib/config/app_config.dart with this IP.
echo     Example: http://192.168.1.5:8000
echo.
echo [3] Server logs will appear below...
echo.
uvicorn main:app --host 0.0.0.0 --port 8000 --reload
pause
