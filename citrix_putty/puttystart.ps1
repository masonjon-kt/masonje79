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
    $password = Request-Password
    return @{ Username = $u; Password = $password.Password; SecurePassword = $password.SecurePassword }
}

# Helper: prompt for a password without changing the current username
function Request-Password {
    do {
        $sp = Read-Host "Enter password" -AsSecureString
        if ($sp.Length -eq 0) {
            Write-Host "Password cannot be empty. Please try again." -ForegroundColor Yellow
        }
    } while ($sp.Length -eq 0)
    $p = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto(
        [System.Runtime.InteropServices.Marshal]::SecureStringToCoTaskMemUnicode($sp)
    )
    return @{ Password = $p; SecurePassword = $sp }
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
colorfg1=0
colorfg2=0
colorfg3=0
colorfg4=0
colorfg5=0
colorfg6=0
colorfg7=0
colorfg8=0
colorfg9=0
colorfg10=0
colorfg11=0
colorfg12=0
colorfg13=0
colorfg14=0
colorfg15=0
colorbg0=1
colorbg1=0
colorbg2=0
colorbg3=0
colorbg4=0
colorbg5=0
colorbg6=0
colorbg7=0
colorbg8=0
colorbg9=0
colorbg10=0
colorbg11=0
colorbg12=0
colorbg13=0
colorbg14=0
colorbg15=0
attribute0=0
attribute1=2097152
attribute2=524288
attribute3=262144
attribute4=65536
attribute5=2621440
attribute6=2359296
attribute7=2162688
attribute8=786432
attribute9=589824
attribute10=327680
attribute11=2883584
attribute12=2621440
attribute13=2424832
attribute14=851968
attribute15=2949120
cursor=2
col=80
scrollback=999
jumpscroll=0
mode=0
loginscheme=UNIX Password
login=1
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
fontname0=1
lines=25
custsize=1
wrap=1
addcr=0
addlf=0
bsdel=0
tabex=0
nocolor=0
nocolor_duplicate=1
monochrome=1
font0=Term;0,0|STD 437 MS-DOS Latin US
font1=TinyTERM Unicode;1,0|Unicode Font
font2=TinyTERM CJK;1,0|Unicode Font
font3=
font4=
font5=

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

# Apply full PuTTY tcxSky session registry settings
$puttyRegContent = @"
Windows Registry Editor Version 5.00

[HKEY_CURRENT_USER\Software\SimonTatham\PuTTY\Sessions\tcxSky]
"TermWidth"=dword:00000050
"TermHeight"=dword:00000019
"ResizeAction"=dword:00000003
"HostName"=""
"PortNumber"=dword:00000016
"AddressFamily"=dword:00000000
"CloseOnExit"=dword:00000001
"WarnOnClose"=dword:00000001
"TCPNoDelay"=dword:00000001
"TCPKeepalives"=dword:00000000
"LogHost"=""
"PreConnectCommand"=""
"ProxyExcludeList"=""
"ProxyDNS"=dword:00000001
"ProxyLocalhost"=dword:00000000
"ProxyMethod"=dword:00000000
"ProxyHost"="proxy"
"ProxyPort"=dword:00000050
"ProxyUsername"=""
"ProxyPassword"=""
"ProxyTelnetCommand"="connect %host %port\\n"
"ProxyLogToTerm"=dword:00000001
"RemoteCommand"=""
"NoPTY"=dword:00000000
"Compression"=dword:00000000
"PreferKnownHostKeys"=dword:00000001
"RekeyTime"=dword:0000003c
"RekeyBytes"="1G"
"TryAgent"=dword:00000001
"AgentFwd"=dword:00000000
"ChangeUsername"=dword:00000000
"PublicKeyFile"=""
"DetachedCertificate"=""
"AuthPlugin"=""
"SshProt"=dword:00000003
"ConnectionSharing"=dword:00000000
"ConnectionSharingUpstream"=dword:00000001
"ConnectionSharingDownstream"=dword:00000001
"SSH2DES"=dword:00000000
"SshNoAuth"=dword:00000000
"SshNoTrivialAuth"=dword:00000000
"SshBanner"=dword:00000001
"AuthTIS"=dword:00000000
"AuthKI"=dword:00000001
"SshNoShell"=dword:00000000
"TerminalType"="xterm"
"TerminalSpeed"="38400,38400"
"UserName"=""
"UserNameFromEnvironment"=dword:00000000
"LocalUserName"=""
"RFCEnviron"=dword:00000000
"PassiveTelnet"=dword:00000000
"SerialLine"="COM1"
"SerialSpeed"=dword:00002580
"SerialDataBits"=dword:00000008
"SerialStopHalfbits"=dword:00000002
"SerialParity"=dword:00000000
"SerialFlowControl"=dword:00000001
"SUPDUPLocation"="The Internet"
"SUPDUPCharset"=dword:00000000
"SUPDUPMoreProcessing"=dword:00000000
"SUPDUPScrolling"=dword:00000000
"BackspaceIsDelete"=dword:00000001
"RXVTHomeEnd"=dword:00000000
"LinuxFunctionKeys"=dword:00000002
"ShiftedArrowKeys"=dword:00000000
"NoApplicationCursors"=dword:00000000
"NoApplicationKeys"=dword:00000000
"NoMouseReporting"=dword:00000000
"NoRemoteResize"=dword:00000000
"NoAltScreen"=dword:00000000
"NoRemoteWinTitle"=dword:00000000
"NoRemoteClearScroll"=dword:00000000
"NoDBackspace"=dword:00000000
"NoRemoteCharset"=dword:00000000
"RemoteQTitleAction"=dword:00000001
"ApplicationCursorKeys"=dword:00000000
"ApplicationKeypad"=dword:00000000
"NetHackKeypad"=dword:00000000
"TelnetKey"=dword:00000000
"TelnetRet"=dword:00000001
"AltF4"=dword:00000001
"AltSpace"=dword:00000000
"AltOnly"=dword:00000000
"LocalEcho"=dword:00000002
"LocalEdit"=dword:00000002
"AlwaysOnTop"=dword:00000000
"FullScreenOnAltEnter"=dword:00000000
"ScrollOnKey"=dword:00000000
"ScrollOnDisp"=dword:00000001
"EraseToScrollback"=dword:00000001
"ComposeKey"=dword:00000000
"CtrlAltKeys"=dword:00000001
"WinTitle"=""
"ScrollbackLines"=dword:000007d0
"DECOriginMode"=dword:00000000
"AutoWrapMode"=dword:00000001
"LFImpliesCR"=dword:00000000
"CurType"=dword:00000000
"BlinkCur"=dword:00000000
"Beep"=dword:00000001
"BeepInd"=dword:00000000
"BellOverload"=dword:00000001
"BellOverloadN"=dword:00000005
"BellWaveFile"=""
"ScrollBar"=dword:00000001
"ScrollBarFullScreen"=dword:00000000
"LockSize"=dword:00000002
"BCE"=dword:00000001
"BlinkText"=dword:00000000
"WinNameAlways"=dword:00000001
"Font"="Courier New"
"FontIsBold"=dword:00000000
"FontCharSet"=dword:00000000
"FontHeight"=dword:0000000a
"FontQuality"=dword:00000000
"LogFileName"="putty.log"
"LogType"=dword:00000000
"LogFileClash"=dword:ffffffff
"LogFlush"=dword:00000001
"LogHeader"=dword:00000001
"SSHLogOmitPasswords"=dword:00000001
"SSHLogOmitData"=dword:00000000
"HideMousePtr"=dword:00000000
"SunkenEdge"=dword:00000000
"WindowBorder"=dword:00000001
"Answerback"="PuTTY"
"Printer"=""
"DisableArabicShaping"=dword:00000000
"DisableBidi"=dword:00000000
"DisableBracketedPaste"=dword:00000000
"ANSIColour"=dword:00000001
"Xterm256Colour"=dword:00000001
"TrueColour"=dword:00000001
"UseSystemColours"=dword:00000000
"TryPalette"=dword:00000000
"BoldAsColour"=dword:00000001
"MouseIsXterm"=dword:00000000
"RectSelect"=dword:00000000
"PasteControls"=dword:00000000
"RawCNP"=dword:00000000
"UTF8linedraw"=dword:00000000
"PasteRTF"=dword:00000000
"MouseOverride"=dword:00000001
"MouseAutocopy"=dword:00000001
"FontVTMode"=dword:00000004
"LineCodePage"=""
"CJKAmbigWide"=dword:00000000
"UTF8Override"=dword:00000001
"CapsLockCyr"=dword:00000000
"X11Forward"=dword:00000000
"X11Display"=""
"X11AuthType"=dword:00000001
"X11AuthFile"=""
"LocalPortAcceptAll"=dword:00000000
"RemotePortAcceptAll"=dword:00000000
"BugIgnore1"=dword:00000000
"BugPlainPW1"=dword:00000000
"BugRSA1"=dword:00000000
"BugIgnore2"=dword:00000000
"BugDeriveKey2"=dword:00000000
"BugRSAPad2"=dword:00000000
"BugPKSessID2"=dword:00000000
"BugRekey2"=dword:00000000
"BugMaxPkt2"=dword:00000000
"BugOldGex2"=dword:00000000
"BugWinadj"=dword:00000000
"BugChanReq"=dword:00000000
"BugDropStart"=dword:00000001
"BugFilterKexinit"=dword:00000001
"BugRSASHA2CertUserauth"=dword:00000000
"BugHMAC2"=dword:00000000
"StampUtmp"=dword:00000001
"LoginShell"=dword:00000001
"ScrollbarOnLeft"=dword:00000000
"ShadowBold"=dword:00000000
"BoldFont"=""
"BoldFontIsBold"=dword:00000000
"BoldFontCharSet"=dword:00000000
"BoldFontHeight"=dword:00000000
"WideFont"=""
"WideFontIsBold"=dword:00000000
"WideFontCharSet"=dword:00000000
"WideFontHeight"=dword:00000000
"WideBoldFont"=""
"WideBoldFontIsBold"=dword:00000000
"WideBoldFontCharSet"=dword:00000000
"WideBoldFontHeight"=dword:00000000
"ShadowBoldOffset"=dword:00000001
"CRImpliesLF"=dword:00000000
"WindowClass"=""
"Present"=dword:00000001
"Protocol"="ssh"
"PingInterval"=dword:00000000
"PingIntervalSecs"=dword:00000000
"TerminalModes"="CS7=A,CS8=A,DISCARD=A,DSUSP=A,ECHO=A,ECHOCTL=A,ECHOE=A,ECHOK=A,ECHOKE=A,ECHONL=A,EOF=A,EOL=A,EOL2=A,ERASE=A,FLUSH=A,ICANON=A,ICRNL=A,IEXTEN=A,IGNCR=A,IGNPAR=A,IMAXBEL=A,INLCR=A,INPCK=A,INTR=A,ISIG=A,ISTRIP=A,IUCLC=A,IUTF8=A,IXANY=A,IXOFF=A,IXON=A,KILL=A,LNEXT=A,NOFLSH=A,OCRNL=A,OLCUC=A,ONLCR=A,ONLRET=A,ONOCR=A,OPOST=A,PARENB=A,PARMRK=A,PARODD=A,PENDIN=A,QUIT=A,REPRINT=A,START=A,STATUS=A,STOP=A,SUSP=A,SWTCH=A,TOSTOP=A,WERASE=A,XCASE=A"
"Environment"=""
"GssapiFwd"=dword:00000000
"Cipher"="aes,chacha20,aesgcm,3des,WARN,des,blowfish,arcfour"
"KEX"="ntru-curve25519,mlkem-curve25519,mlkem-nist,ecdh,dh-gex-sha1,dh-group18-sha512,dh-group17-sha512,dh-group16-sha512,dh-group15-sha512,dh-group14-sha1,rsa,WARN,dh-group1-sha1"
"HostKey"="ed448,ed25519,ecdsa,rsa,dsa,WARN"
"GssapiRekey"=dword:00000002
"AuthGSSAPI"=dword:00000001
"AuthGSSAPIKEX"=dword:00000001
"GSSLibs"="gssapi32,sspi,custom"
"GSSCustom"=""
"BellOverloadT"=dword:000007d0
"BellOverloadS"=dword:00001388
"Colour0"="187,187,187"
"Colour1"="255,255,255"
"Colour2"="0,0,0"
"Colour3"="85,85,85"
"Colour4"="0,0,0"
"Colour5"="0,255,0"
"Colour6"="0,0,0"
"Colour7"="85,85,85"
"Colour8"="187,0,0"
"Colour9"="255,85,85"
"Colour10"="0,187,0"
"Colour11"="85,255,85"
"Colour12"="187,187,0"
"Colour13"="255,255,85"
"Colour14"="0,0,187"
"Colour15"="85,85,255"
"Colour16"="187,0,187"
"Colour17"="255,85,255"
"Colour18"="0,187,187"
"Colour19"="85,255,255"
"Colour20"="187,187,187"
"Colour21"="255,255,255"
"Wordness0"="0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0"
"Wordness32"="0,1,2,1,1,1,1,1,1,1,1,1,1,2,2,2,2,2,2,2,2,2,2,2,2,2,1,1,1,1,1,1"
"Wordness64"="1,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,1,1,1,1,2"
"Wordness96"="1,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,1,1,1,1,1"
"Wordness128"="1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1"
"Wordness160"="1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1"
"Wordness192"="2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,1,2,2,2,2,2,2,2,2"
"Wordness224"="2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,1,2,2,2,2,2,2,2,2"
"MousePaste"="explicit"
"CtrlShiftIns"="explicit"
"CtrlShiftCV"="none"
"PortForwardings"=""
"SSHManualHostKeys"=""
"@

$puttyRegFile = Join-Path $env:TEMP "puttystart_tcxSky.reg"
$puttyRegContent | Set-Content -Path $puttyRegFile -Encoding Unicode
$null = reg import $puttyRegFile 2>&1

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
$portalOpened = $false
$today = (Get-Date).ToString("yyyy-MM-dd")

if (Test-Path $configPath) {
    $cfg = (Get-Content $configPath -Raw) -replace '\\', '\\\\' | ConvertFrom-StringData
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
        Write-Host "Saved password is from $($cfg.PwdDate). Opening password portal..." -ForegroundColor Yellow
        Set-Location "C:\Program Files (x86)\Microsoft\Edge\Application\"
        Start-Process "C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe" "https://possecurity-prod.cdengpos.rch-cdc-cdeprod.kroger.com/#/"
        $portalOpened = $true
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
    if (-not $portalOpened) {
        Start-Process "C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe" "https://possecurity-prod.cdengpos.rch-cdc-cdeprod.kroger.com/#/"
        $portalOpened = $true
    }
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
    Write-Host "  Endpoint: $lastEnvironment  |  't' = change tools  |  'c' = credentials mgmt  |  'e' = change endpoint  |  'x' = exit" -ForegroundColor DarkGray

    # Prompt for store (accepts special commands)
    $storePrompt = "Store (e.g., ci123 / fc.ci123 / FQDN / IP)"
    if ($lastStore) { $storePrompt += " [default: $lastStore]" }

    $storeInput = Read-Host $storePrompt

    if ($storeInput -eq "t") { break }
    if ($storeInput -eq "x") { exit 0 }
    if ($storeInput -eq "c") {
        while ($true) {
        Write-Host "`nCredential Management:" -ForegroundColor Cyan
        Write-Host "1. Update daily password (PWD)" -ForegroundColor White
        Write-Host "2. Copy current password to clipboard" -ForegroundColor White
        Write-Host "3. Add/update static credentials for a store" -ForegroundColor White
        Write-Host "4. Remove static credentials for a store" -ForegroundColor White
        Write-Host "5. List stores with static credentials" -ForegroundColor White
        Write-Host "6. Exit" -ForegroundColor White
        $credAction = Read-Host "Select (1-6)"
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
                if ($Password) {
                    Set-Clipboard -Value $Password
                    Write-Host "Current password copied to clipboard." -ForegroundColor Green
                } else {
                    Write-Host "No password currently loaded." -ForegroundColor Yellow
                }
            }
            "3" {
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
            "4" {
                $storeKey = (Read-Host "Enter store number to remove").ToLower()
                if ($staticCreds.ContainsKey($storeKey)) {
                    $staticCreds.Remove($storeKey)
                    Save-Config -termChoice $savedTermChoice -ftChoice $savedFtChoice -username $Username -securePassword $SecurePassword -lastStore $lastStore -lastEnvironment $lastEnvironment -staticCredsTable $staticCreds
                    Write-Host "Static credentials removed for $storeKey." -ForegroundColor Green
                } else {
                    Write-Host "No static credentials found for '$storeKey'." -ForegroundColor Yellow
                }
            }
            "5" {
                if ($staticCreds.Count -eq 0) {
                    Write-Host "No static credentials stored." -ForegroundColor Yellow
                } else {
                    Write-Host "Stores with static credentials:" -ForegroundColor Cyan
                    foreach ($store in ($staticCreds.Keys | Sort-Object)) {
                        Write-Host "  $store  (user: $($staticCreds[$store].Username))" -ForegroundColor White
                    }
                }
            }
            "6" { break }
        }
        if ($credAction -eq "6" -or $credAction -eq "2") { break }
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
    # If entry matches standard store format (2 letters + 3 digits), build Kroger hostname.
    # If entry matches endpoint.store format (e.g. fc.ci123 or cc.ci123), append .kroger.com.
    # Otherwise, use the entry directly as a hostname or IP address.
    if ($Store -match '^[a-zA-Z]{2}\d{3}$') {
        $TargetHost = "$Environment.$Store.kroger.com"
    } elseif ($Store -match '^[a-zA-Z]{2,}\.[a-zA-Z]{2}\d{3}$') {
        $TargetHost = "$Store.kroger.com"
    } else {
        $TargetHost = $Store
        Write-Host "Non-standard entry — connecting directly to: $TargetHost" -ForegroundColor DarkYellow
    }

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
        if ($Verbose) { Write-Host "  CMD: `"$puttyPath`" -load tcxSky -ssh $ConnUsername@$TargetHost -P $Port -pw *****" -ForegroundColor DarkYellow }
        & $puttyPath -load "tcxSky" -ssh "$ConnUsername@$TargetHost" -P $Port -pw $ConnPassword
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
                elseif ($_ -like "login=*")  { "login=1" }
                elseif ($_ -like "loginsw=*")  { "loginsw=1" }
                elseif ($_ -like "loginW1=*")  { "loginW1=password:" }
                elseif ($_ -like "loginS1=*")  { "loginS1=$ConnPassword^M" }
                elseif ($_ -like "loginW2=*")  { "loginW2=password:" }
                elseif ($_ -like "loginS2=*")  { "loginS2=$ConnPassword^M" }
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
