# This script automates a temporary workaround for WSL2 networking issues with VPNs.
# It configures mirrored networking mode and sets a static resolv.conf.
# Remember to revert the resolv.conf changes manually when the VPN is disconnected.

# Define the default DNS server to use in resolv.conf
# IMPORTANT: Change this to the DNS server IP you get from 'ipconfig.exe /all'
# while your VPN is connected. Using a public DNS like 8.8.8.8 might also work.
$nameserver = "8.8.8.8" # Using Google DNS as a default example

# --- Check for Administrator privileges ---
if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Host "This script needs to be run with administrative privileges." -ForegroundColor Red
    Write-Host "Right-click the PowerShell icon and choose 'Run as administrator'." -ForegroundColor Red
    exit 1
}

Write-Host "Applying WSL2 networking fix using mirrored mode..." -ForegroundColor Green
Write-Host "NOTE: This is a temporary fix. Remember to revert resolv.conf when VPN is disconnected." -ForegroundColor Yellow

# --- Configure .wslconfig (Windows side) ---
$wslConfigPath = Join-Path $env:USERPROFILE ".wslconfig"
Write-Host "Configuring .wslconfig at $wslConfigPath" -ForegroundColor Yellow

$wslConfigContent = if (Test-Path $wslConfigPath) { Get-Content $wslConfigPath -Encoding UTF8 } else { @() }
# Remove existing networkingMode and [wsl2] section if it's just the header
$newWslConfigContent = $wslConfigContent | Where-Object { $_ -notmatch "^\s*networkingMode\s*=" -and $_ -notmatch "^\s*\[wsl2\]\s*$" }

# Add [wsl2] section if it doesn't exist
if ($newWslConfigContent -notmatch "^\s*\[wsl2\]") {
    $newWslConfigContent += "[wsl2]"
}
$newWslConfigContent += "networkingMode=mirrored"

try {
    $newWslConfigContent | Set-Content $wslConfigPath -Encoding UTF8
    Write-Host ".wslconfig configured successfully." -ForegroundColor Green
} catch {
    Write-Host "Error writing to .wslconfig: $($_.Exception.Message)" -ForegroundColor Red
    Write-Host "Please ensure you have write permissions or run as administrator." -ForegroundColor Red
    exit 1
}

# --- Configure /etc/wsl.conf (WSL side) ---
Write-Host "Configuring /etc/wsl.conf inside your default WSL distribution..." -ForegroundColor Yellow

# Check if /etc/wsl.conf exists and read its content via wsl -e
# Using -e stat is more robust than Test-Path with wsl.exe
$wslConfCheckResult = wsl.exe -e stat /etc/wsl.conf 2>&1 # Capture stderr
$wslConfExists = ($LASTEXITCODE -eq 0 -and $wslConfCheckResult -notmatch "No such file or directory")

$wslConfContent = if ($wslConfExists) { wsl.exe -e cat /etc/wsl.conf } else { @() }
# Remove existing generateResolvConf and [network] section if it's just the header
$newWslConfContent = $wslConfContent | Where-Object { $_ -notmatch "^\s*generateResolvConf\s*=" -and $_ -notmatch "^\s*\[network\]\s*$" }

# Add [network] section if it doesn't exist
if ($newWslConfContent -notmatch "^\s*\[network\]") {
     $newWslConfContent += "[network]"
}
$newWslConfContent += "generateResolvConf=false"

# Use a temporary file and sudo to write the content inside WSL
$tempWslConfContent = $newWslConfContent | Out-String
$tempFileName = "wslconf_temp_$([int](Get-Random * 10000)).conf"
# Ensure temp file is in a location accessible by wsl.exe
$tempFilePathWindows = Join-Path $env:TEMP $tempFileName
$wslTempDir = "/mnt/c/Users/$($env:USERNAME)/AppData/Local/Temp" # Common temp path in WSL

try {
    $tempWslConfContent | Set-Content $tempFilePathWindows -Encoding UTF8

    # Use wsl.exe to copy the temp file from Windows temp to WSL temp, then use sudo to move it
    wsl.exe --cd "$wslTempDir" -e bash -c "sudo cp '$tempFileName' /etc/wsl.conf"

    Write-Host "/etc/wsl.conf configured successfully." -ForegroundColor Green

} catch {
     Write-Host "Error configuring /etc/wsl.conf inside WSL: $($_.Exception.Message)" -ForegroundColor Red
     Write-Host "Please ensure your default WSL distribution is running and you can use sudo without issues." -ForegroundColor Red
     exit 1
} finally {
     # Clean up temp file on Windows side
     if (Test-Path $tempFilePathWindows) { Remove-Item $tempFilePathWindows -Force }
     # Clean up temp file in WSL temp dir (requires sudo if created by sudo cp)
     wsl.exe --cd "$wslTempDir" -e bash -c "sudo rm -f '$tempFileName'" # Use -f just in case
}


# --- Shut down WSL ---
Write-Host "Shutting down WSL to apply changes..." -ForegroundColor Yellow
wsl.exe --shutdown
Write-Host "WSL shut down." -ForegroundColor Green

# --- Prompt User to Restart WSL ---
Write-Host "`n==================================================="
Write-Host "ACTION REQUIRED:" -ForegroundColor Cyan
Write-Host "Please open your Ubuntu/WSL instance now." -ForegroundColor Cyan
Write-Host "Once your WSL terminal is open and ready, press Enter to continue this script." -ForegroundColor Cyan
Write-Host "==================================================="
Pause

# --- Remove old resolv.conf and create new one (WSL side) ---
Write-Host "Configuring /etc/resolv.conf inside WSL..." -ForegroundColor Yellow

try {
    # Remove existing resolv.conf (could be symlink or old file)
    wsl.exe -e sudo rm -f /etc/resolv.conf
    Write-Host "Removed old /etc/resolv.conf." -ForegroundColor Green

    # Create the new static resolv.conf with the specified nameserver
    # Use a temp file and sudo tee to ensure correct permissions and content
    $resolvContent = "nameserver $($nameserver)`n" # Add newline
    $tempResolvFileName = "resolv_temp_$([int](Get-Random * 10000)).conf"
    $tempResolvFilePathWindows = Join-Path $env:TEMP $tempResolvFileName

    $resolvContent | Set-Content $tempResolvFilePathWindows -Encoding UTF8

    # Copy temp file to WSL temp dir and use sudo tee to write to /etc/resolv.conf
    wsl.exe --cd "$wslTempDir" -e bash -c "sudo tee /etc/resolv.conf < '$tempResolvFileName'"

    Write-Host "Created new /etc/resolv.conf with nameserver: $nameserver" -ForegroundColor Green

    # Removed the chattr +i step as this is a temporary fix

} catch {
    Write-Host "Error configuring /etc/resolv.conf inside WSL: $($_.Exception.Message)" -ForegroundColor Red
    Write-Host "Please ensure your default WSL distribution is running and you can use sudo without issues." -ForegroundColor Red
    exit 1
} finally {
     # Clean up temp resolv file on Windows side
     if (Test-Path $tempResolvFilePathWindows) { Remove-Item $tempResolvFilePathWindows -Force }
     # Clean up temp resolv file in WSL temp dir (requires sudo if created by sudo cp/tee)
     wsl.exe --cd "$wslTempDir" -e bash -c "sudo rm -f '$tempResolvFileName'" # Use -f just in case
}

Write-Host "`nWSL networking fix applied successfully!" -ForegroundColor Green
Write-Host "You should now have internet connectivity in your Ubuntu instance even with VPN enabled." -ForegroundColor Green
Write-Host "Remember to manually revert resolv.conf when you disconnect your VPN." -ForegroundColor Yellow
Write-Host "See the README for instructions on reverting." -ForegroundColor Yellow
