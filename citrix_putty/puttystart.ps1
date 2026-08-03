# PuTTY SSH connection to Kroger environments
# Prompts for endpoint and store, launches PuTTY sessions in a loop

param(
    [string]$Port = "22"
)

# Prompt for username with default value
$Username = Read-Host "Enter username [default: 4690]"
if (-not $Username) {
    $Username = "4690"
}

# Prompt for password once (masked) with reprompt on empty input
do {
    $SecurePassword = Read-Host "Enter password" -AsSecureString
    if ($SecurePassword.Length -eq 0) {
        Write-Host "Password cannot be empty. Please try again." -ForegroundColor Yellow
    }
} while ($SecurePassword.Length -eq 0)

$Password = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto(
    [System.Runtime.InteropServices.Marshal]::SecureStringToCoTaskMemUnicode($SecurePassword)
)

# Validate initial inputs
if (-not $Username -or -not $Password) {
    Write-Error "Username and password are required."
    exit 1
}

# Check if PuTTY is installed
$puttyPath = "C:\Program Files\PuTTY\putty.exe"
if (-not (Test-Path $puttyPath)) {
    $puttyPath = "C:\Program Files (x86)\PuTTY\putty.exe"
}
if (-not (Test-Path $puttyPath)) {
    Write-Error "PuTTY not found. Please install PuTTY or update the path in this script."
    exit 1
}

# Check if FileZilla is installed
$filezillaPath = "C:\Program Files\FileZilla FTP Client\filezilla.exe"
if (-not (Test-Path $filezillaPath)) {
    $filezillaPath = "C:\Program Files (x86)\FileZilla FTP Client\filezilla.exe"
}

# Check if WinSCP is installed
$winscpPath = "C:\Program Files\WinSCP\WinSCP.exe"
if (-not (Test-Path $winscpPath)) {
    $winscpPath = "C:\Program Files (x86)\WinSCP\WinSCP.exe"
}

$SftpPort = "22"
$lastEnvironment = "mc"
$lastStore = ""

# Tool selection loop
while ($true) {
    # Prompt for which tools to use
    Write-Host "`nWhich tool(s) do you want to use for each connection?" -ForegroundColor Cyan
    Write-Host "1. PuTTY only (SSH terminal)" -ForegroundColor White
    Write-Host "2. FileZilla only (SFTP file transfer)" -ForegroundColor White
    Write-Host "3. Both PuTTY and FileZilla" -ForegroundColor White
    Write-Host "4. WinSCP only (SFTP file transfer - single window)" -ForegroundColor White
    Write-Host "5. Both PuTTY and WinSCP" -ForegroundColor White

    $toolChoice = Read-Host "Enter choice (1-5) [default: 1]"
    if (-not $toolChoice) {
        $toolChoice = "1"
    }

    $usePutty = $false
    $useFilezilla = $false
    $useWinSCP = $false

    switch ($toolChoice) {
        "1" { $usePutty = $true }
        "2" { $useFilezilla = $true }
        "3" { $usePutty = $true; $useFilezilla = $true }
        "4" { $useWinSCP = $true }
        "5" { $usePutty = $true; $useWinSCP = $true }
        default { $usePutty = $true }
    }

    if ($useFilezilla -and -not (Test-Path $filezillaPath)) {
        Write-Host "FileZilla not found at expected locations." -ForegroundColor Yellow
        Write-Host "FileZilla will not be launched." -ForegroundColor Yellow
        $useFilezilla = $false
    }

    if ($useWinSCP -and -not (Test-Path $winscpPath)) {
        Write-Host "WinSCP not found at expected locations." -ForegroundColor Yellow
        Write-Host "WinSCP can be downloaded from https://winscp.net" -ForegroundColor Yellow
        $useWinSCP = $false
    }

# Main connection loop
while ($true) {
    Write-Host "`n--- New Connection ---" -ForegroundColor Cyan
    
    # Prompt for endpoint with default value (uses last entered endpoint)
    $Environment = Read-Host "Enter endpoint (mc, cc, fc, etc.) [default: $lastEnvironment] or 't' to change tools"
    if (-not $Environment) {
        $Environment = $lastEnvironment
    }
    
    # Check if user wants to return to tool selection menu
    if ($Environment -eq "t") {
        break
    }
    
    $lastEnvironment = $Environment
    
    # Prompt for store with reprompt on empty input (uses last entered store as default)
    $storePrompt = "Enter store number (e.g., ci123)"
    if ($lastStore) {
        $storePrompt += " [default: $lastStore]"
    }
    
    do {
        $Store = Read-Host $storePrompt
        if (-not $Store) {
            if ($lastStore) {
                $Store = $lastStore
            } else {
                Write-Host "Store number cannot be empty. Please try again." -ForegroundColor Yellow
            }
        }
    } while (-not $Store)
    
    $lastStore = $Store
    
    # Construct target host
    $TargetHost = "$Environment.$Store.kroger.com"
    
    Write-Host "Connecting to: $TargetHost as $Username" -ForegroundColor Green
    
    # Copy password to clipboard
    $Password | Set-Clipboard
    Write-Host "Password copied to clipboard." -ForegroundColor Green
    
    # Launch PuTTY if selected
    if ($usePutty) {
        Write-Host "Launching PuTTY..." -ForegroundColor Cyan
        & $puttyPath -l $Username -P $Port $TargetHost
    }
    
    # Launch FileZilla if selected
    if ($useFilezilla) {
        Write-Host "Launching FileZilla..." -ForegroundColor Cyan
        & $filezillaPath "sftp://$Username`:$Password@${TargetHost}:$SftpPort"
    }

    # Launch WinSCP if selected
    if ($useWinSCP) {
        Write-Host "Launching WinSCP..." -ForegroundColor Cyan
        & $winscpPath "sftp://$Username`:$Password@${TargetHost}:$SftpPort"
    }
    
    if ($usePutty -or $useFilezilla -or $useWinSCP) {
        Write-Host "Session(s) closed. Ready for next connection." -ForegroundColor Yellow
    }
}
}
