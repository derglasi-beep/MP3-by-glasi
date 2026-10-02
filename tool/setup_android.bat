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
echo Android-Plattform wurde erzeugt.
echo Als naechstes: flutter pub get
echo Danach: flutter run -d android
