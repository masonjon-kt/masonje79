# PuTTY SSH connection to Kroger environments
# Prompts for endpoint and store, launches PuTTY sessions in a loop

param(
    [string]$Port = "22"
)

# Helper: prompt for credentials and return them
function Request-Credentials {
    $u = Read-Host "Enter username [default: 4690]"
    if (-not $u) { $u = "4690" }
    do {
        $sp = Read-Host "Enter password" -AsSecureString
        if ($sp.Length -eq 0) {
            Write-Host "Password cannot be empty. Please try again." -ForegroundColor Yellow
        }
    } while ($sp.Length -eq 0)
    $p = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto(
        [System.Runtime.InteropServices.Marshal]::SecureStringToCoTaskMemUnicode($sp)
    )
    return @{ Username = $u; Password = $p; SecurePassword = $sp }
}

# Check if PuTTY is installed
$puttyPath = "C:\Program Files\PuTTY\putty.exe"
if (-not (Test-Path $puttyPath)) {
    $puttyPath = "C:\Program Files (x86)\PuTTY\putty.exe"
}
if (-not (Test-Path $puttyPath)) {
    Write-Host "PuTTY not found. PuTTY will not be available as a terminal option." -ForegroundColor Yellow
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

# Check if TinyTerm is installed
$tinytermPath = "C:\Program Files\Century\TinyTERM\tt.exe"
if (-not (Test-Path $tinytermPath)) {
    $tinytermPath = "C:\Program Files (x86)\Century\TinyTERM\tt.exe"
}

$SftpPort = "22"
$lastEnvironment = "mc"
$lastStore = ""

# Config file in same directory as this script
$configPath = Join-Path $PSScriptRoot "puttystart.cfg"

# Helper: save all settings to config file
function Save-Config {
    param($termChoice, $ftChoice, $username, $securePassword, $lastStore = "", $lastEnvironment = "mc")
    $encryptedPw = $securePassword | ConvertFrom-SecureString
    $today = (Get-Date).ToString("yyyy-MM-dd")
    @"
TermChoice=$termChoice
FtChoice=$ftChoice
Username=$username
PasswordEncrypted=$encryptedPw
PasswordDate=$today
LastStore=$lastStore
LastEnvironment=$lastEnvironment
"@ | Set-Content $configPath
}

# Load saved config
$savedTermChoice = "1"
$savedFtChoice = "0"
$Username = "4690"
$Password = $null
$SecurePassword = $null
$today = (Get-Date).ToString("yyyy-MM-dd")

if (Test-Path $configPath) {
    $cfg = Get-Content $configPath | ConvertFrom-StringData
    if ($cfg.TermChoice)          { $savedTermChoice  = $cfg.TermChoice }
    if ($cfg.FtChoice)            { $savedFtChoice    = $cfg.FtChoice }
    if ($cfg.Username)            { $Username         = $cfg.Username }
    if ($cfg.LastStore)           { $lastStore        = $cfg.LastStore }
    if ($cfg.LastEnvironment)     { $lastEnvironment  = $cfg.LastEnvironment }
    if ($cfg.PasswordEncrypted -and $cfg.PasswordDate -eq $today) {
        # Same day — decrypt and reuse stored password
        try {
            $SecurePassword = $cfg.PasswordEncrypted | ConvertTo-SecureString
            $Password = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto(
                [System.Runtime.InteropServices.Marshal]::SecureStringToCoTaskMemUnicode($SecurePassword)
            )
            Write-Host "Using saved credentials for $Username (saved today)." -ForegroundColor Green
        } catch {
            Write-Host "Could not decrypt saved password. Please re-enter credentials." -ForegroundColor Yellow
        }
    } elseif ($cfg.PasswordDate -and $cfg.PasswordDate -ne $today) {
        Write-Host "Saved password is from $($cfg.PasswordDate). Please enter today's password." -ForegroundColor Yellow
    }
}

# Prompt for credentials if not loaded from config
if (-not $Password) {
    $creds = Request-Credentials
    $Username      = $creds.Username
    $Password      = $creds.Password
    $SecurePassword = $creds.SecurePassword
}

# Tool selection loop
$firstRun = $true
while ($true) {
    # On first run, use saved preferences and skip the menu
    if ($firstRun) {
        $termChoice = $savedTermChoice
        $ftChoice   = $savedFtChoice
        $firstRun   = $false
    } else {
        # --- Terminal selection ---
        Write-Host "`nTerminal session:" -ForegroundColor Cyan
        Write-Host "0. None" -ForegroundColor White
        Write-Host "1. PuTTY" -ForegroundColor White
        Write-Host "2. TinyTerm" -ForegroundColor White

        $termChoice = Read-Host "Select terminal (0-2) [default: $savedTermChoice]"
        if (-not $termChoice) { $termChoice = $savedTermChoice }

        # --- File transfer selection ---
        Write-Host "`nFile transfer session:" -ForegroundColor Cyan
        Write-Host "0. None" -ForegroundColor White
        Write-Host "1. FileZilla" -ForegroundColor White
        Write-Host "2. WinSCP" -ForegroundColor White

        $ftChoice = Read-Host "Select file transfer (0-2) [default: $savedFtChoice]"
        if (-not $ftChoice) { $ftChoice = $savedFtChoice }

        $savedTermChoice = $termChoice
        $savedFtChoice   = $ftChoice
        Save-Config -termChoice $savedTermChoice -ftChoice $savedFtChoice -username $Username -securePassword $SecurePassword
    }

    # Apply tool flags from chosen values
    $usePutty    = ($termChoice -eq "1")
    $useTinyTerm = ($termChoice -eq "2")
    $useFilezilla = ($ftChoice -eq "1")
    $useWinSCP    = ($ftChoice -eq "2")

    if ($usePutty -and -not (Test-Path $puttyPath)) {
        Write-Host "PuTTY not found. Terminal will not be launched." -ForegroundColor Yellow
        $usePutty = $false
    }
    if ($useTinyTerm -and -not (Test-Path $tinytermPath)) {
        Write-Host "TinyTerm not found at expected locations. Terminal will not be launched." -ForegroundColor Yellow
        $useTinyTerm = $false
    }
    if ($useFilezilla -and -not (Test-Path $filezillaPath)) {
        Write-Host "FileZilla not found at expected locations. File transfer will not be launched." -ForegroundColor Yellow
        $useFilezilla = $false
    }
    if ($useWinSCP -and -not (Test-Path $winscpPath)) {
        Write-Host "WinSCP not found at expected locations. File transfer will not be launched." -ForegroundColor Yellow
        Write-Host "WinSCP can be downloaded from https://winscp.net" -ForegroundColor Yellow
        $useWinSCP = $false
    }

    Write-Host "`nActive: Terminal=$(if($usePutty){'PuTTY'}elseif($useTinyTerm){'TinyTerm'}else{'None'})  FileTransfer=$(if($useFilezilla){'FileZilla'}elseif($useWinSCP){'WinSCP'}else{'None'})" -ForegroundColor DarkCyan

# Main connection loop
while ($true) {
    Write-Host "`n--- New Connection ---" -ForegroundColor Cyan
    Write-Host "  Endpoint: $lastEnvironment  |  't' = change tools  |  'c' = change credentials  |  'e' = change endpoint" -ForegroundColor DarkGray

    # Prompt for store (accepts special commands)
    $storePrompt = "Enter store number (e.g., ci123)"
    if ($lastStore) { $storePrompt += " [default: $lastStore]" }

    $storeInput = Read-Host $storePrompt

    if ($storeInput -eq "t") { break }
    if ($storeInput -eq "c") {
        $creds = Request-Credentials
        $Username       = $creds.Username
        $Password       = $creds.Password
        $SecurePassword = $creds.SecurePassword
        Save-Config -termChoice $savedTermChoice -ftChoice $savedFtChoice -username $Username -securePassword $SecurePassword -lastStore $lastStore -lastEnvironment $lastEnvironment
        Write-Host "Credentials updated." -ForegroundColor Green
        continue
    }
    if ($storeInput -eq "e") {
        $newEnv = Read-Host "Enter endpoint (mc, cc, fc, etc.) [default: $lastEnvironment]"
        if ($newEnv) { $lastEnvironment = $newEnv }
        Save-Config -termChoice $savedTermChoice -ftChoice $savedFtChoice -username $Username -securePassword $SecurePassword -lastStore $lastStore -lastEnvironment $lastEnvironment
        continue
    }

    $Store = $storeInput
    if (-not $Store) {
        if ($lastStore) {
            $Store = $lastStore
        } else {
            Write-Host "Store number cannot be empty. Please try again." -ForegroundColor Yellow
            continue
        }
    }

    $lastStore = $Store
    $Environment = $lastEnvironment
    
    $lastStore = $Store
    
    # Construct target host
    $TargetHost = "$Environment.$Store.kroger.com"
    
    # Save last store and endpoint to config
    Save-Config -termChoice $savedTermChoice -ftChoice $savedFtChoice -username $Username -securePassword $SecurePassword -lastStore $lastStore -lastEnvironment $lastEnvironment
    
    Write-Host "Connecting to: $TargetHost as $Username" -ForegroundColor Green
    
    # Copy password to clipboard
    $Password | Set-Clipboard
    Write-Host "Password copied to clipboard." -ForegroundColor Green
    
    # Launch PuTTY if selected
    if ($usePutty) {
        Write-Host "Launching PuTTY..." -ForegroundColor Cyan
        & $puttyPath -l $Username -P $Port $TargetHost
    }

    # Launch TinyTerm if selected
    if ($useTinyTerm) {
        Write-Host "Launching TinyTerm..." -ForegroundColor Cyan
        & $tinytermPath "ssh://$Username`:$Password@${TargetHost}:$Port"
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
    
    if ($usePutty -or $useTinyTerm -or $useFilezilla -or $useWinSCP) {
        Write-Host "Session(s) closed. Ready for next connection." -ForegroundColor Yellow
    }
}
}
