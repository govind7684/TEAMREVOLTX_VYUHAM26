# Puts the CIVINEX logo on the phone's launcher icon and start-up screen.
# Run once from the project folder:  powershell -ExecutionPolicy Bypass -File tools\apply_logo.ps1
$ErrorActionPreference = 'Stop'
flutter pub get
dart run flutter_launcher_icons
dart run flutter_native_splash:create
Write-Host "Done. Uninstall the old app from the phone, then run: flutter run (or flutter build apk)"
