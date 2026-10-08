@echo off
setlocal
cd /d "%~dp0"

for /f "tokens=2" %%V in ('findstr /b "version:" pubspec.yaml') do set "APP_VERSION=%%V"
for /f "tokens=1 delims=+" %%V in ("%APP_VERSION%") do set "APP_VERSION=%%V"

echo.
echo MP3 by Glasi - Release APK v%APP_VERSION%
echo ========================================
echo.

flutter pub get
if errorlevel 1 exit /b 1

flutter build apk --release
if errorlevel 1 exit /b 1

if not exist "dist" mkdir "dist"
copy /Y "build\app\outputs\flutter-apk\app-release.apk" "dist\MP3-by-Glasi-v%APP_VERSION%.apk" >nul
if errorlevel 1 exit /b 1

echo.
echo Fertig:
echo %CD%\dist\MP3-by-Glasi-v%APP_VERSION%.apk
echo.
endlocal
