$ErrorActionPreference = 'Stop'
$cfgPath = 'android\app\google-services.json'
if (-not (Test-Path $cfgPath)) { Write-Host "Missing $cfgPath. The app cannot use Firebase without it."; exit 1 }
$cfg = Get-Content $cfgPath -Raw | ConvertFrom-Json
$apiKey = $cfg.client[0].api_key[0].current_key
$project = $cfg.project_info.project_id
Write-Host "Firebase project in the app: $project"
$email = (Read-Host 'Email').Trim()
$sec = Read-Host 'Password (hidden)' -AsSecureString
$pw = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto([System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($sec))
try {
  $body = @{ email = $email; password = $pw; returnSecureToken = $true } | ConvertTo-Json
  $r = Invoke-RestMethod -Method Post -ContentType 'application/json' -Body $body -Uri "https://identitytoolkit.googleapis.com/v1/accounts:signInWithPassword?key=$apiKey"
} catch {
  $msg = $_.ErrorDetails.Message
  if (-not $msg) { $msg = $_.Exception.Message }
  Write-Host "SIGN-IN FAILED: $msg"
  exit 1
}
Write-Host "SIGN-IN OK. uid = $($r.localId)"
try {
  $doc = Invoke-RestMethod -Headers @{ Authorization = "Bearer $($r.idToken)" } -Uri "https://firestore.googleapis.com/v1/projects/$project/databases/(default)/documents/users/$($r.localId)"
  $f = $doc.fields
  Write-Host "PROFILE FOUND: role = $($f.role.stringValue), active = $($f.active | ConvertTo-Json -Compress), email = $($f.email.stringValue)"
} catch {
  $msg = $_.ErrorDetails.Message
  if (-not $msg) { $msg = $_.Exception.Message }
  Write-Host "PROFILE NOT READ: $msg"
}
