# Run from the project folder:   powershell -ExecutionPolicy Bypass -File tools\fix_android.ps1
# Prepares the Android project for CIVINEX AI. Safe to run more than once: it
# only changes what is missing.
#   1. permissions: internet, location, biometric (fingerprint / face unlock)
#   2. app name
#   3. minimum Android version 7.0 (needed for the encrypted document vault)
#   4. MainActivity -> FlutterFragmentActivity (needed by the fingerprint dialog)
#   5. Firebase: google-services.json copied to android\app, Google services Gradle plugin,
#      applicationId = com.civinex.civinex_ai (must match google-services.json)

$ErrorActionPreference = "Stop"
$manifest = "android\app\src\main\AndroidManifest.xml"
if (-not (Test-Path $manifest)) {
  Write-Host "Cannot find $manifest. Run this from the civinex_ai folder." -ForegroundColor Red
  exit 1
}
$utf8 = New-Object System.Text.UTF8Encoding($false)
$any = $false

# ---- 1 + 2: manifest ----
$xml = [System.IO.File]::ReadAllText((Resolve-Path $manifest))
$changed = $false
$perms = @(
  "android.permission.INTERNET",
  "android.permission.ACCESS_FINE_LOCATION",
  "android.permission.ACCESS_COARSE_LOCATION",
  "android.permission.USE_BIOMETRIC"
)
foreach ($p in $perms) {
  if ($xml -notmatch [regex]::Escape($p)) {
    $line = "    <uses-permission android:name=`"$p`"/>`r`n"
    $xml = $xml -replace "(<manifest[^>]*>\s*)", "`$1`r`n$line"
    $changed = $true
    Write-Host "Added $p"
  }
}
if ($xml -match 'android:label="civinex_ai"') {
  $xml = $xml -replace 'android:label="civinex_ai"', 'android:label="CIVINEX AI"'
  $changed = $true
  Write-Host "Set app name to CIVINEX AI"
}
if ($xml -notmatch 'usesCleartextTraffic') {
  # The laptop assistant server is plain http on the local network.
  $xml = $xml -replace '<application', '<application android:usesCleartextTraffic="true"'
  $changed = $true
  Write-Host "Allowed http to the local assistant server"
}
if ($changed) {
  [System.IO.File]::WriteAllText((Resolve-Path $manifest), $xml, $utf8)
  $any = $true
}

# ---- 3: minSdk ----
foreach ($g in @("android\app\build.gradle.kts", "android\app\build.gradle")) {
  if (Test-Path $g) {
    $text = [System.IO.File]::ReadAllText((Resolve-Path $g))
    $new = $text -replace 'minSdk\s*=\s*flutter\.minSdkVersion', 'minSdk = 24'
    $new = $new -replace 'minSdkVersion\s+flutter\.minSdkVersion', 'minSdkVersion 24'
    if ($new -ne $text) {
      [System.IO.File]::WriteAllText((Resolve-Path $g), $new, $utf8)
      Write-Host "Set minimum Android version to 7.0 (API 24) in $g"
      $any = $true
    }
  }
}

# ---- 4: MainActivity ----
$activity = Get-ChildItem -Path "android\app\src\main" -Recurse -Include MainActivity.kt, MainActivity.java -ErrorAction SilentlyContinue | Select-Object -First 1
if ($activity) {
  $text = [System.IO.File]::ReadAllText($activity.FullName)
  if ($text -match 'FlutterActivity' -and $text -notmatch 'FlutterFragmentActivity') {
    $new = $text -replace 'io\.flutter\.embedding\.android\.FlutterActivity', 'io.flutter.embedding.android.FlutterFragmentActivity'
    $new = $new -replace '\bFlutterActivity\b', 'FlutterFragmentActivity'
    [System.IO.File]::WriteAllText($activity.FullName, $new, $utf8)
    Write-Host "MainActivity now extends FlutterFragmentActivity"
    $any = $true
  }
} else {
  Write-Host "Could not find MainActivity. Change it by hand: see docs/SETUP_GUIDE.md" -ForegroundColor Yellow
}

# ---- 5: Firebase ----
$pkg = "com.civinex.civinex_ai"
$gs = "android\app\google-services.json"
if (-not (Test-Path $gs)) {
  foreach ($c in @("google-services.json", "$env:USERPROFILE\Downloads\google-services.json")) {
    if (Test-Path $c) { Copy-Item $c $gs; Write-Host "Copied google-services.json from $c"; $any = $true; break }
  }
}
if (-not (Test-Path $gs)) {
  Write-Host "google-services.json not found. Put it in android\app\ (from Firebase console > Project settings)." -ForegroundColor Yellow
}
foreach ($g in @("android\app\build.gradle.kts", "android\app\build.gradle")) {
  if (Test-Path $g) {
    $text = [System.IO.File]::ReadAllText((Resolve-Path $g))
    $new = $text
    $new = $new -replace 'applicationId\s*=\s*"[^"]*"', "applicationId = `"$pkg`""
    $new = $new -replace 'applicationId\s+"[^"]*"', "applicationId `"$pkg`""
    $new = $new -replace 'namespace\s*=\s*"[^"]*"', "namespace = `"$pkg`""
    $new = $new -replace 'namespace\s+"[^"]*"', "namespace `"$pkg`""
    if ($new -notmatch 'com\.google\.gms\.google-services') {
      if ($g -like "*.kts") {
        $new = $new -replace '(id\("dev\.flutter\.flutter-gradle-plugin"\))', "`$1`r`n    id(`"com.google.gms.google-services`")"
      } else {
        $new = $new -replace "(id\s+`"dev\.flutter\.flutter-gradle-plugin`")", "`$1`r`n    id `"com.google.gms.google-services`""
      }
    }
    if ($new -ne $text) {
      [System.IO.File]::WriteAllText((Resolve-Path $g), $new, $utf8)
      Write-Host "Updated $g for Firebase (applicationId $pkg, google-services plugin)"
      $any = $true
    }
  }
}
foreach ($g in @("android\settings.gradle.kts", "android\settings.gradle")) {
  if (Test-Path $g) {
    $text = [System.IO.File]::ReadAllText((Resolve-Path $g))
    if ($text -notmatch 'com\.google\.gms\.google-services') {
      if ($g -like "*.kts") {
        $new = $text -replace '(id\("org\.jetbrains\.kotlin\.android"\)[^\r\n]*)', "`$1`r`n    id(`"com.google.gms.google-services`") version `"4.5.0`" apply false"
      } else {
        $new = $text -replace "(id\s+`"org\.jetbrains\.kotlin\.android`"[^\r\n]*)", "`$1`r`n    id `"com.google.gms.google-services`" version `"4.5.0`" apply false"
      }
      if ($new -ne $text) {
        [System.IO.File]::WriteAllText((Resolve-Path $g), $new, $utf8)
        Write-Host "Added Google services plugin to $g"
        $any = $true
      } else {
        Write-Host "Could not edit $g automatically. See docs/FIREBASE_SETUP.md step 'Gradle'." -ForegroundColor Yellow
      }
    }
  }
}

if ($any) {
  Write-Host "Android project updated. Now run:  flutter clean ; flutter pub get ; flutter run" -ForegroundColor Green
} else {
  Write-Host "Android project already has everything." -ForegroundColor Green
}
