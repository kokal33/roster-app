Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  ROSTER - Tablet Update Script" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

# Step 1: Get ADB
Write-Host "[1/7] Setting up ADB..." -ForegroundColor White
$adbPath = $null
if (Get-Command adb -ErrorAction SilentlyContinue) {
    $adbPath = "adb"
    Write-Host "[OK] ADB already installed" -ForegroundColor Green
} else {
    Write-Host "Downloading ADB..."
    $zipUrl = "https://dl.google.com/android/repository/platform-tools-latest-windows.zip"
    $zipFile = "$env:TEMP\platform-tools.zip"
    $extractDir = "$env:TEMP\platform-tools"
    
    Invoke-WebRequest -Uri $zipUrl -OutFile $zipFile
    Expand-Archive -Path $zipFile -DestinationPath $env:TEMP -Force
    Remove-Item $zipFile -Force
    
    $adbPath = "$extractDir\adb.exe"
    if (!(Test-Path $adbPath)) {
        Write-Host "ERROR: Failed to download ADB!" -ForegroundColor Red
        exit 1
    }
    Write-Host "[OK] ADB downloaded" -ForegroundColor Green
}

# Step 2: Check tablet is connected
Write-Host ""
Write-Host "[2/7] Checking tablet connection..." -ForegroundColor White
Write-Host "Make sure the tablet is connected via USB and USB debugging is ON" -ForegroundColor Yellow
Write-Host ""
Read-Host "Press ENTER when ready"

$devices = & $adbPath devices 2>&1 | Out-String
if ($devices -notmatch "\t device") {
    # Try to kill and restart adb server
    & $adbPath kill-server 2>$null
    Start-Sleep -Seconds 2
    & $adbPath start-server 2>$null
    Start-Sleep -Seconds 3
    $devices = & $adbPath devices 2>&1 | Out-String
    if ($devices -notmatch "\t device") {
        Write-Host "No tablet detected! Check USB cable and USB debugging." -ForegroundColor Red
        exit 1
    }
}
Write-Host "[OK] Tablet connected" -ForegroundColor Green

# Step 3: Check root access
Write-Host ""
Write-Host "[3/7] Checking root access..." -ForegroundColor White
$rootCheck = & $adbPath shell su 0 id 2>&1 | Out-String
if ($rootCheck -notmatch "uid=0") {
    Write-Host "ERROR: Tablet is not rooted!" -ForegroundColor Red
    Write-Host "The old app is locked as device owner."
    Write-Host "Without root, the only option is a FACTORY RESET."
    Write-Host ""
    Write-Host "To factory reset: hold Power + Volume Down for 10 seconds,"
    Write-Host "then select Wipe Data/Factory Reset."
    Write-Host "After reset, skip all Google accounts, then re-run this script."
    exit 1
}
Write-Host "[OK] Root access available" -ForegroundColor Green

# Step 4: Remove device owner + disable old app
Write-Host ""
Write-Host "[4/7] Removing device owner lock..." -ForegroundColor White
& $adbPath shell su 0 rm /data/system/device_owner_2.xml 2>$null
& $adbPath shell su 0 rm /data/system/device_policies.xml 2>$null
& $adbPath shell su 0 am force-stop com.nfccheckin 2>$null
& $adbPath shell su 0 pm disable com.nfccheckin 2>$null
Write-Host "[OK] Device lock removed, old app disabled" -ForegroundColor Green

# Step 5: Reboot and wait
Write-Host ""
Write-Host "[5/7] Rebooting tablet..." -ForegroundColor White
& $adbPath reboot
Write-Host "Waiting for tablet to restart (about 60 seconds)..."
Start-Sleep -Seconds 15
& $adbPath wait-for-device
Start-Sleep -Seconds 20

$bootComplete = ""
while ($bootComplete -ne "1") {
    Start-Sleep -Seconds 3
    $bootComplete = (& $adbPath shell getprop sys.boot_completed 2>$null).Trim()
}
Start-Sleep -Seconds 5
Write-Host "[OK] Tablet rebooted" -ForegroundColor Green

# Step 6: Uninstall old app
Write-Host ""
Write-Host "[6/7] Uninstalling old app..." -ForegroundColor White
& $adbPath shell pm enable com.nfccheckin 2>$null
& $adbPath uninstall com.nfccheckin 2>$null
Write-Host "[OK] Old app removed" -ForegroundColor Green

# Step 7: Download and install new app
Write-Host ""
Write-Host "[7/7] Downloading and installing latest ROSTER app..." -ForegroundColor White

$release = Invoke-RestMethod -Uri "https://api.github.com/repos/kokal33/roster-app/releases/latest" -Headers @{"Accept"="application/vnd.github+json"}
$apkAsset = $release.assets | Where-Object { $_.name -like "*.apk" } | Select-Object -First 1

if (-not $apkAsset) {
    Write-Host "Could not find APK download!" -ForegroundColor Red
    exit 1
}

$tempApk = "$env:TEMP\roster-app.apk"
Write-Host "Downloading..."
Invoke-WebRequest -Uri $apkAsset.browser_download_url -OutFile $tempApk

& $adbPath install $tempApk
if ($LASTEXITCODE -ne 0) {
    Write-Host "Install failed!" -ForegroundColor Red
    exit 1
}
Remove-Item $tempApk -Force

# Launch
& $adbPath shell am start -n com.nfccheckin/.SetupActivity

Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  DONE! ROSTER is installed." -ForegroundColor Green
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "The tablet shows the setup screen."
Write-Host "Scan the QR code from the admin panel to pair it."
Write-Host ""
Read-Host "Press ENTER to close"
