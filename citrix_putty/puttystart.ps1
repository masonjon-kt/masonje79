# PuTTY SSH connection to Kroger environments
# Prompts for endpoint and store, launches PuTTY sessions in a loop
#
# Usage:
#   .\puttystart.ps1 [-Port <port>] [-v]
#
# Parameters:
#   -Port <port>   SSH port to connect on. Default: 22
#   -v             Verbose mode. Prints the exact command being run before each
#                  tool launch (password is masked with *****).
#
# Runtime commands (entered at the store prompt):
#   t   Open tool selection menu (change terminal / file transfer app)
#   c   Open credential management menu (update daily PWD, manage static creds)
#   e   Change the current endpoint (mc, cc, fc, etc.)
#
# Examples:
#   .\puttystart.ps1                 # Normal run, defaults to port 22
#   .\puttystart.ps1 -v              # Verbose — shows launch commands
#   .\puttystart.ps1 -Port 2222      # Connect on a non-standard SSH port

param(
    [string]$Port = "22",
    [switch]$v
)

$Verbose = $v.IsPresent

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
$staticCreds = @{}  # key: store (lowercase), value: @{Username; Password; SecurePassword}

# Config file in same directory as this script
$configPath = Join-Path $PSScriptRoot "puttystart.cfg"

# Helper: save all settings to config file
function Save-Config {
    param($termChoice, $ftChoice, $username, $securePassword, $lastStore = "", $lastEnvironment = "mc", $staticCredsTable = $null)
    $encryptedPw = $securePassword | ConvertFrom-SecureString
    $today = (Get-Date).ToString("yyyy-MM-dd")
    $lines = @(
        "TermChoice=$termChoice",
        "FtChoice=$ftChoice",
        "Username=$username",
        "PwdEncrypted=$encryptedPw",
        "PwdDate=$today",
        "LastStore=$lastStore",
        "LastEnvironment=$lastEnvironment"
    )
    if ($staticCredsTable) {
        foreach ($store in $staticCredsTable.Keys | Sort-Object) {
            $sc = $staticCredsTable[$store]
            $encStatic = $sc.SecurePassword | ConvertFrom-SecureString
            $lines += "Static_${store}_Username=$($sc.Username)"
            $lines += "Static_${store}_Password=$encStatic"
        }
    }
    $lines -join "`n" | Set-Content $configPath
}

# Load saved config
$savedTermChoice = "1"
$savedFtChoice = "0"
$Username = "4690"
$Password = $null
$SecurePassword = $null
$today = (Get-Date).ToString("yyyy-MM-dd")

if (Test-Path $configPath) {
    $cfg = Get-Content $configPath -Raw | ConvertFrom-StringData
    if ($cfg.TermChoice)          { $savedTermChoice  = $cfg.TermChoice }
    if ($cfg.FtChoice)            { $savedFtChoice    = $cfg.FtChoice }
    if ($cfg.Username)            { $Username         = $cfg.Username }
    if ($cfg.LastStore)           { $lastStore        = $cfg.LastStore }
    if ($cfg.LastEnvironment)     { $lastEnvironment  = $cfg.LastEnvironment }
    if ($cfg.PwdEncrypted -and $cfg.PwdDate -eq $today) {
        # Same day — decrypt and reuse stored password
        try {
            $SecurePassword = $cfg.PwdEncrypted | ConvertTo-SecureString
            $Password = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto(
                [System.Runtime.InteropServices.Marshal]::SecureStringToCoTaskMemUnicode($SecurePassword)
            )
            Write-Host "Using saved credentials for $Username (saved today)." -ForegroundColor Green
        } catch {
            Write-Host "Could not decrypt saved password. Please re-enter credentials." -ForegroundColor Yellow
        }
    } elseif ($cfg.PwdDate -and $cfg.PwdDate -ne $today) {
        Write-Host "Saved password is from $($cfg.PasswordDate). Opening password portal..." -ForegroundColor Yellow
        Set-Location "C:\Program Files (x86)\Microsoft\Edge\Application\"
        Start-Process "C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe" "https://possecurity-prod.cdengpos.rch-cdc-cdeprod.kroger.com/#/"
    }

    # Load static credentials
    foreach ($key in $cfg.Keys) {
        if ($key -match '^Static_(.+)_Username$') {
            $store = $Matches[1].ToLower()
            if (-not $staticCreds.ContainsKey($store)) { $staticCreds[$store] = @{} }
            $staticCreds[$store].Username = $cfg[$key]
        } elseif ($key -match '^Static_(.+)_Password$') {
            $store = $Matches[1].ToLower()
            if (-not $staticCreds.ContainsKey($store)) { $staticCreds[$store] = @{} }
            try {
                $sp = $cfg[$key] | ConvertTo-SecureString
                $staticCreds[$store].SecurePassword = $sp
                $staticCreds[$store].Password = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto(
                    [System.Runtime.InteropServices.Marshal]::SecureStringToCoTaskMemUnicode($sp)
                )
            } catch {
                Write-Host "Could not decrypt static credentials for store '$store'." -ForegroundColor Yellow
            }
        }
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
        Save-Config -termChoice $savedTermChoice -ftChoice $savedFtChoice -username $Username -securePassword $SecurePassword -staticCredsTable $staticCreds
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
        Write-Host "`nCredential Management:" -ForegroundColor Cyan
        Write-Host "1. Update daily password (PWD)" -ForegroundColor White
        Write-Host "2. Add/update static credentials for a store" -ForegroundColor White
        Write-Host "3. Remove static credentials for a store" -ForegroundColor White
        Write-Host "4. List stores with static credentials" -ForegroundColor White
        Write-Host "5. Cancel" -ForegroundColor White
        $credAction = Read-Host "Select (1-5)"
        switch ($credAction) {
            "1" {
                $creds = Request-Credentials
                $Username       = $creds.Username
                $Password       = $creds.Password
                $SecurePassword = $creds.SecurePassword
                Save-Config -termChoice $savedTermChoice -ftChoice $savedFtChoice -username $Username -securePassword $SecurePassword -lastStore $lastStore -lastEnvironment $lastEnvironment -staticCredsTable $staticCreds
                Write-Host "Daily credentials updated." -ForegroundColor Green
            }
            "2" {
                $storeKey = (Read-Host "Enter store number to set static credentials for").ToLower()
                if ($storeKey) {
                    $staticUser = Read-Host "Enter username for $storeKey [default: $Username]"
                    if (-not $staticUser) { $staticUser = $Username }
                    do {
                        $staticSp = Read-Host "Enter static password for $storeKey" -AsSecureString
                        if ($staticSp.Length -eq 0) { Write-Host "Password cannot be empty." -ForegroundColor Yellow }
                    } while ($staticSp.Length -eq 0)
                    $staticP = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto(
                        [System.Runtime.InteropServices.Marshal]::SecureStringToCoTaskMemUnicode($staticSp)
                    )
                    $staticCreds[$storeKey] = @{ Username = $staticUser; Password = $staticP; SecurePassword = $staticSp }
                    Save-Config -termChoice $savedTermChoice -ftChoice $savedFtChoice -username $Username -securePassword $SecurePassword -lastStore $lastStore -lastEnvironment $lastEnvironment -staticCredsTable $staticCreds
                    Write-Host "Static credentials saved for $storeKey." -ForegroundColor Green
                }
            }
            "3" {
                $storeKey = (Read-Host "Enter store number to remove").ToLower()
                if ($staticCreds.ContainsKey($storeKey)) {
                    $staticCreds.Remove($storeKey)
                    Save-Config -termChoice $savedTermChoice -ftChoice $savedFtChoice -username $Username -securePassword $SecurePassword -lastStore $lastStore -lastEnvironment $lastEnvironment -staticCredsTable $staticCreds
                    Write-Host "Static credentials removed for $storeKey." -ForegroundColor Green
                } else {
                    Write-Host "No static credentials found for '$storeKey'." -ForegroundColor Yellow
                }
            }
            "4" {
                if ($staticCreds.Count -eq 0) {
                    Write-Host "No static credentials stored." -ForegroundColor Yellow
                } else {
                    Write-Host "Stores with static credentials:" -ForegroundColor Cyan
                    foreach ($store in ($staticCreds.Keys | Sort-Object)) {
                        Write-Host "  $store  (user: $($staticCreds[$store].Username))" -ForegroundColor White
                    }
                }
            }
        }
        continue
    }
    if ($storeInput -eq "e") {
        $newEnv = Read-Host "Enter endpoint (mc, cc, fc, etc.) [default: $lastEnvironment]"
        if ($newEnv) { $lastEnvironment = $newEnv }
        Save-Config -termChoice $savedTermChoice -ftChoice $savedFtChoice -username $Username -securePassword $SecurePassword -lastStore $lastStore -lastEnvironment $lastEnvironment -staticCredsTable $staticCreds
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

    # Construct target host
    $TargetHost = "$Environment.$Store.kroger.com"

    # Save last store and endpoint to config
    Save-Config -termChoice $savedTermChoice -ftChoice $savedFtChoice -username $Username -securePassword $SecurePassword -lastStore $lastStore -lastEnvironment $lastEnvironment -staticCredsTable $staticCreds

    # Resolve credentials: static per-store overrides daily PWD
    $storeKey = $Store.ToLower()
    if ($staticCreds.ContainsKey($storeKey) -and $staticCreds[$storeKey].Password) {
        $ConnUsername = $staticCreds[$storeKey].Username
        $ConnPassword = $staticCreds[$storeKey].Password
        Write-Host "Connecting to: $TargetHost as $ConnUsername  [STATIC credentials]" -ForegroundColor Green
    } else {
        $ConnUsername = $Username
        $ConnPassword = $Password
        Write-Host "Connecting to: $TargetHost as $ConnUsername  [PWD credentials]" -ForegroundColor Green
    }

    # Copy password to clipboard
    $ConnPassword | Set-Clipboard
    Write-Host "Password copied to clipboard." -ForegroundColor Green

    # Launch PuTTY if selected
    if ($usePutty) {
        Write-Host "Launching PuTTY..." -ForegroundColor Cyan
        if ($Verbose) { Write-Host "  CMD: `"$puttyPath`" -l $ConnUsername -P $Port $TargetHost" -ForegroundColor DarkYellow }
        & $puttyPath -l $ConnUsername -P $Port $TargetHost
    }

    # Launch TinyTerm if selected
    if ($useTinyTerm) {
        Write-Host "Launching TinyTerm..." -ForegroundColor Cyan
        if ($Verbose) { Write-Host "  CMD: `"$tinytermPath`" ssh://$ConnUsername`:*****@${TargetHost}:$Port" -ForegroundColor DarkYellow }
        & $tinytermPath "ssh://$ConnUsername`:$ConnPassword@${TargetHost}:$Port"
    }

    # Launch FileZilla if selected
    if ($useFilezilla) {
        Write-Host "Launching FileZilla..." -ForegroundColor Cyan
        if ($Verbose) { Write-Host "  CMD: `"$filezillaPath`" sftp://$ConnUsername`:*****@${TargetHost}:$SftpPort" -ForegroundColor DarkYellow }
        & $filezillaPath "sftp://$ConnUsername`:$ConnPassword@${TargetHost}:$SftpPort"
    }

    # Launch WinSCP if selected
    if ($useWinSCP) {
        Write-Host "Launching WinSCP..." -ForegroundColor Cyan
        if ($Verbose) { Write-Host "  CMD: `"$winscpPath`" sftp://$ConnUsername`:*****@${TargetHost}:$SftpPort" -ForegroundColor DarkYellow }
        & $winscpPath "sftp://$ConnUsername`:$ConnPassword@${TargetHost}:$SftpPort"
    }
    
    if ($usePutty -or $useTinyTerm -or $useFilezilla -or $useWinSCP) {
        Write-Host "Session(s) closed. Ready for next connection." -ForegroundColor Yellow
    }
}
}
