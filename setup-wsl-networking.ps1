# Define the default DNS server to use in resolv.conf
# You can change this to your preferred DNS server (e.g., your VPN's DNS, 1.1.1.1, 8.8.8.8)
$nameserver = "8.8.8.8" # Using Google DNS as a default example

# --- Check for Administrator privileges ---
if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Host "This script needs to be run with administrative privileges." -ForegroundColor Red
    Write-Host "Right-click the PowerShell icon and choose 'Run as administrator'." -ForegroundColor Red
    exit 1
}

Write-Host "Applying WSL2 networking fix using mirrored mode..." -ForegroundColor Green

# --- Configure .wslconfig (Windows side) ---
$wslConfigPath = Join-Path $env:USERPROFILE ".wslconfig"
Write-Host "Configuring .wslconfig at $wslConfigPath" -ForegroundColor Yellow

$wslConfigContent = if (Test-Path $wslConfigPath) { Get-Content $wslConfigPath -Encoding UTF8 } else { @() }
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
$wslConfCheck = wsl.exe -e stat /etc/wsl.conf 2>$null
$wslConfExists = ($LASTEXITCODE -eq 0)

$wslConfContent = if ($wslConfExists) { wsl.exe -e cat /etc/wsl.conf } else { @() }
$newWslConfContent = $wslConfContent | Where-Object { $_ -notmatch "^\s*generateResolvConf\s*=" -and $_ -notmatch "^\s*\[network\]\s*$" }

# Add [network] section if it doesn't exist
if ($newWslConfContent -notmatch "^\s*\[network\]") {
     $newWslConfContent += "[network]"
}
$newWslConfContent += "generateResolvConf=false"

# Use a temporary file and sudo to write the content inside WSL
$tempWslConfContent = $newWslConfContent | Out-String
$tempFileName = "wslconf_temp_$([int](Get-Random * 10000)).conf"
$tempFilePathWindows = Join-Path $env:TEMP $tempFileName

try {
    $tempWslConfContent | Set-Content $tempFilePathWindows -Encoding UTF8
    # Copy temp file to WSL and overwrite /etc/wsl.conf using sudo
    wsl.exe -- "$([System.IO.Path]::GetTempPath())" -c "sudo cp '$tempFileName' /etc/wsl.conf"
    # Clean up temp file in WSL temp dir
    wsl.exe -- "$([System.IO.Path]::GetTempPath())" -c "rm '$tempFileName'"

    Write-Host "/etc/wsl.conf configured successfully." -ForegroundColor Green

} catch {
     Write-Host "Error configuring /etc/wsl.conf inside WSL: $($_.Exception.Message)" -ForegroundColor Red
     Write-Host "Please ensure your default WSL distribution is running and you can use sudo without issues." -ForegroundColor Red
     exit 1
} finally {
     # Clean up temp file on Windows side
     if (Test-Path $tempFilePathWindows) { Remove-Item $tempFilePathWindows -Force }
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
    $resolvContent = "nameserver $($nameserver)`n" # Add newline
    wsl.exe -e sudo bash -c "echo '$resolvContent' > /etc/resolv.conf"
    Write-Host "Created new /etc/resolv.conf with nameserver: $nameserver" -ForegroundColor Green

    # Make resolv.conf immutable
    wsl.exe -e sudo chattr +i /etc/resolv.conf
    Write-Host "Made /etc/resolv.conf immutable." -ForegroundColor Green

} catch {
    Write-Host "Error configuring /etc/resolv.conf inside WSL: $($_.Exception.Message)" -ForegroundColor Red
    Write-Host "Please ensure your default WSL distribution is running and you can use sudo without issues." -ForegroundColor Red
    exit 1
}

Write-Host "`nWSL networking fix applied successfully!" -ForegroundColor Green
Write-Host "You should now have internet connectivity in your Ubuntu instance even with VPN enabled." -ForegroundColor Green
Write-Host "Remember to run 'sudo chattr -i /etc/resolv.conf' if you ever need to edit resolv.conf again." -ForegroundColor Yellow