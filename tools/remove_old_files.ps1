# Run once from the project folder after unzipping update5 over your project:
#   powershell -ExecutionPolicy Bypass -File tools\remove_old_files.ps1
# Deletes files that no longer exist in this version (they would otherwise fail to compile).
$old = @(
  "lib\features\auth\login_screen.dart",
  "lib\features\auth\setup_screen.dart",
  "lib\features\profile\profile_screen.dart",
  "lib\core\constants\app_config.dart",
  "lib\data\demo_data\demo_seeder.dart",
  "test\widgets\login_test.dart"
)
foreach ($f in $old) {
  if (Test-Path $f) { Remove-Item $f -Force; Write-Host "Removed $f" }
}
if ((Test-Path "lib\data\demo_data") -and -not (Get-ChildItem "lib\data\demo_data")) { Remove-Item "lib\data\demo_data" }
if ((Test-Path "lib\features\profile") -and -not (Get-ChildItem "lib\features\profile")) { Remove-Item "lib\features\profile" }
Write-Host "Done. Now: flutter pub get ; flutter analyze ; flutter test" -ForegroundColor Green
