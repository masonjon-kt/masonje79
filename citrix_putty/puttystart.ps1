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
    [string]$Port = $null,
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

if (-not $Port) { $Port = "22" }
$SftpPort = $Port
$lastEnvironment = "mc"
$lastStore = ""
$staticCreds = @{}  # key: store (lowercase), value: @{Username; Password; SecurePassword}

# Built-in TinyTerm .emu template — written to temp at startup
$builtInEmuTemplate = @"
[Application]
SaveOnExit=0

[Session]
ProtectSettings=1
ExtendLinesOnResize=1

[term.emu]
emulate=13
colorfg0=8
colorbg0=1
scrollback=999
mode=0
loginscheme=UNIX Password
login=0
user=
password=
loginsw=0
loginW1=
loginS1=
loginW2=
loginS2=
autoconnect=1
autocmd=0
CommLink=1
Keyboard=1
lines=25
col=80
wrap=1
monochrome=0

[term.ft]
protocol=1
txblksiz=16384
txwindow=16384
zmodem32=1

[term.comm]
node=
port=22
commtype=5
wordlen=8
stopbits=0
parity=0
xon=17
xoff=19
sshport=22
sshcipher=3
sshCompLevel=9
sshtype=0

[term.gen]
editor=notepad.exe
remark=Generated Template

learnmode=0
learnfile=0
errormsg=1
iconfile=
iconid=
macro=0
sessionbar=0
menubar=1
ribbon=0
splash=0
altkeys=0
tooltips=1
tooltime=1
protect=0
language=0
ddeenable=0
ddetimeout=
ddename=
xwindow=854
ywindow=207
wwindows=800
hwindows=540
winwmode=0
servertype=0
requirelogin=1
allownewuser=1
allowxfer=1
allowchat=1
banner=banner.txt
motd=motd.txt
autoanswer=0
autobaud=0
portnum=23
author=author
date=date
subject=subject
version=version
email=email
NewConn=1
hmtype=0
RibbonSize=1
OleStatusBar=0
OleRibbonBar=1
OleTapInStg=0
OleSessionBar=1
statusbar=1
SaveType=2
OleClose=1
OleShowDlg=1
errbox=1
address=1
scriptfile=
scptcmd=0
pstxfrscrpt=
scptstartup=
scptconnect=0
scptlogin=
scptlogoff=
scptdiscon=
scptsesext=
idxsessrt=0
idxconnect=0
idxlogin=0
idxlogoff=0
idxdiscon=0
idxsesext=0
scptindex=1
srtsvrlst=
srtsvridx=0
stpsvrlst=
stpsvridx=0
keymacroind=0
keymacrolist=KeyMac##.cs
keymacrofile=
copyaddcr=0
keybar=0
autowindowtitle=
frameKeyboardFile=
frameKeyboard=

[term.sys]
CLASS=term
LANGUAGE=us

[Fonts]
FontName1=TermCS1
FontName2=Term

"@

$builtInEmuPath = Join-Path $env:TEMP "puttystart_template.emu"
$builtInEmuTemplate | Set-Content -Path $builtInEmuPath -Encoding ASCII

$TinyTermTemplate = $builtInEmuPath  # default; config can override with a custom path

# Config file in same directory as this script
$configPath = Join-Path $PSScriptRoot "puttystart.cfg"

# Helper: save all settings to config file
function Save-Config {
    param($termChoice, $ftChoice, $username, $securePassword, $lastStore = "", $lastEnvironment = "mc", $staticCredsTable = $null, $port = "22", $tinyTermTemplate = "")
    $encryptedPw = $securePassword | ConvertFrom-SecureString
    $today = (Get-Date).ToString("yyyy-MM-dd")
    $lines = @(
        "TermChoice=$termChoice",
        "FtChoice=$ftChoice",
        "Port=$port",
        "TinyTermTemplate=$tinyTermTemplate",
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
    if ($cfg.TinyTermTemplate)    { $TinyTermTemplate = $cfg.TinyTermTemplate }
    # Command-line -Port takes precedence; fall back to config, then default 22
    if (-not $Port) {
        if ($cfg.Port)            { $Port = $cfg.Port }
        else                      { $Port = "22" }
    }
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
    Write-Host "Opening password portal..." -ForegroundColor Yellow
    Start-Process "C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe" "https://possecurity-prod.cdengpos.rch-cdc-cdeprod.kroger.com/#/"
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

        # --- Port configuration ---
        $newPort = Read-Host "SSH/SFTP port [default: $Port]"
        if ($newPort) { $Port = $newPort }
        $SftpPort = $Port

        # --- TinyTerm template path ---
        if ($termChoice -eq "2") {
            $tmplPrompt = "TinyTerm .emu template path"
            if ($TinyTermTemplate) { $tmplPrompt += " [default: $TinyTermTemplate]" }
            $newTemplate = Read-Host $tmplPrompt
            if ($newTemplate) { $TinyTermTemplate = $newTemplate }
            if ($TinyTermTemplate -and -not (Test-Path $TinyTermTemplate)) {
                Write-Host "Warning: template file not found: $TinyTermTemplate" -ForegroundColor Yellow
            }
        }

        $savedTermChoice = $termChoice
        $savedFtChoice   = $ftChoice
        Save-Config -termChoice $savedTermChoice -ftChoice $savedFtChoice -username $Username -securePassword $SecurePassword -staticCredsTable $staticCreds -port $Port -tinyTermTemplate $TinyTermTemplate

        # --- Verbose toggle ---
        $verboseToggle = Read-Host "Verbose mode (shows launch commands) [current: $(if($Verbose){'ON'}else{'OFF'})] — press Enter to keep, or type 'on'/'off' to change"
        if ($verboseToggle -eq 'on')  { $Verbose = $true  }
        if ($verboseToggle -eq 'off') { $Verbose = $false }
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

    Write-Host "`nActive: Terminal=$(if($usePutty){'PuTTY'}elseif($useTinyTerm){'TinyTerm'}else{'None'})  FileTransfer=$(if($useFilezilla){'FileZilla'}elseif($useWinSCP){'WinSCP'}else{'None'})  Port=$Port  Verbose=$(if($Verbose){'ON'}else{'OFF'})" -ForegroundColor DarkCyan

# Main connection loop
while ($true) {
    Write-Host "`n--- New Connection ---" -ForegroundColor Cyan
    Write-Host "  Endpoint: $lastEnvironment  |  't' = change tools  |  'c' = change credentials  |  'e' = change endpoint  |  'x' = exit" -ForegroundColor DarkGray

    # Prompt for store (accepts special commands)
    $storePrompt = "Enter store number (e.g., ci123)"
    if ($lastStore) { $storePrompt += " [default: $lastStore]" }

    $storeInput = Read-Host $storePrompt

    if ($storeInput -eq "t") { break }
    if ($storeInput -eq "x") { exit 0 }
    if ($storeInput -eq "c") {
        while ($true) {
        Write-Host "`nCredential Management:" -ForegroundColor Cyan
        Write-Host "1. Update daily password (PWD)" -ForegroundColor White
        Write-Host "2. Add/update static credentials for a store" -ForegroundColor White
        Write-Host "3. Remove static credentials for a store" -ForegroundColor White
        Write-Host "4. List stores with static credentials" -ForegroundColor White
        Write-Host "5. Exit" -ForegroundColor White
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
            "5" { break }
        }
        if ($credAction -eq "5") { break }
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
        if ($Verbose) { Write-Host "  CMD: `"$puttyPath`" -ssh $ConnUsername@$TargetHost -P $Port -pw *****" -ForegroundColor DarkYellow }
        & $puttyPath -ssh "$ConnUsername@$TargetHost" -P $Port -pw $ConnPassword
    }

    # Launch TinyTerm if selected
    if ($useTinyTerm) {
        Write-Host "Launching TinyTerm..." -ForegroundColor Cyan
        if ($TinyTermTemplate -and (Test-Path $TinyTermTemplate)) {
            # Template-based method: inject host/user and use login macros for password
            $tmpTpx = Join-Path $env:TEMP "puttystart_session.tpx"
            (Get-Content -Path $TinyTermTemplate) | ForEach-Object {
                if ($_ -like "node=*")         { "node=$TargetHost" }
                elseif ($_ -like "user=*")     { "user=$ConnUsername" }
                elseif ($_ -like "password=*") { "password=" }
                elseif ($_ -like "remark=*")   { "remark=$TargetHost" }
                elseif ($_ -like "loginsw=*")  { "loginsw=1" }
                elseif ($_ -like "loginW2=*")  { "loginW2=Please enter your password:" }
                elseif ($_ -like "loginS2=*")  { "loginS2=^W$ConnPassword^M" }
                else { $_ }
            } | Set-Content -Path $tmpTpx -Encoding ASCII
            $ttArgs = "-t `"$tmpTpx`" -nosplash -nas"
            if ($Verbose) { Write-Host "  CMD: `"$tinytermPath`" -t `"$tmpTpx`" -nosplash " -ForegroundColor DarkYellow }
            Start-Process -FilePath $tinytermPath -ArgumentList $ttArgs
        } else {
            if ($TinyTermTemplate) {
                Write-Host "  Warning: TinyTerm template not found: $TinyTermTemplate" -ForegroundColor Yellow
                Write-Host "  Update via 't' > tool menu to set a valid template path." -ForegroundColor Yellow
            } else {
                Write-Host "  No TinyTerm template configured. Set one via 't' > tool menu." -ForegroundColor Yellow
            }
        }
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
