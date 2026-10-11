@echo off
setlocal

cd /d "%~dp0"

set "FLUTTER=C:\src\flutter\bin\flutter.bat"

if not exist "%FLUTTER%" (
  echo Flutter wurde nicht unter C:\src\flutter gefunden.
  echo Bitte pruefe deinen Flutter-SDK-Pfad.
  exit /b 1
)

echo.
echo === Windows-Unterbau erzeugen ===
call "%FLUTTER%" create --platforms=windows .
if errorlevel 1 exit /b %errorlevel%

echo.
echo === Abhaengigkeiten laden ===
call "%FLUTTER%" pub get
if errorlevel 1 exit /b %errorlevel%

echo.
echo === Optionalen Native-Assets-Ordner sicherstellen ===
if not exist "build\native_assets\windows" mkdir "build\native_assets\windows"

echo.
echo === MP3 by Glasi unter Windows starten ===
call "%FLUTTER%" run -d windows

endlocal
