@echo off
setlocal

where flutter >nul 2>&1
if errorlevel 1 (
  echo.
  echo FEHLER: Flutter wurde nicht gefunden.
  echo.
  echo Installiere Flutter und fuege den Ordner "flutter\bin" zur PATH-Umgebungsvariable hinzu.
  echo Danach ein neues CMD-Fenster oeffnen und "flutter --version" testen.
  echo.
  exit /b 1
)

echo Erzeuge die Android-Plattformdateien...
flutter create --platforms=android .
if errorlevel 1 (
  echo.
  echo FEHLER: Flutter konnte die Android-Plattform nicht erzeugen.
  exit /b 1
)

echo.
echo Konfiguriere Android Media Service...
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0configure_android_media.ps1"
if errorlevel 1 (
  echo.
  echo WARNUNG: Android Media Service konnte nicht automatisch konfiguriert werden.
  exit /b 1
)
echo Android-Plattform wurde erzeugt und fuer Hintergrundwiedergabe konfiguriert.
echo Als naechstes: flutter pub get
echo Danach: flutter run -d android
