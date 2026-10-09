#!/usr/bin/env bash
# SSH connection helper for Kroger environments (bash port of puttystart.ps1)
# Prompts for endpoint and store, launches terminal / file-transfer sessions in a loop.
#
# Usage:
#   ./puttystart.sh [-P <port>] [-v]
#
# Options:
#   -P, --port <port>  SSH port to connect on. Default: 22
#   -v, --verbose      Print the exact command being run before each launch
#                      (password is masked with *****).
#   -h, --help         Show this help.
#
# Runtime commands (entered at the store prompt):
#   u                 Usage help
#   t                 Open tool selection menu (change terminal / file transfer app)
#   c                 Open credential management menu (update daily PWD, static creds)
#   e                 Change the current endpoint (mc, cc, fc, etc.)
#   x                 Exit
#   s|w [<host>]    Launch ssh / sftp for one host
#
# Examples:
#   ./puttystart.sh              # Normal run, defaults to port 22
#   ./puttystart.sh -v           # Verbose - shows launch commands
#   ./puttystart.sh -P 2222      # Connect on a non-standard SSH port
#   Store prompt: s mc.ci123     # Launch only ssh for this host

set -uo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_PATH="$SCRIPT_DIR/puttystart.sh.cfg"
PORTAL_URL="https://possecurity-prod.cdengpos.rch-cdc-cdeprod.kroger.com/#/"

C_RESET=$'\033[0m'; C_CYAN=$'\033[36m'; C_GREEN=$'\033[32m'
C_YELLOW=$'\033[33m'; C_DKCYAN=$'\033[36;2m'; C_DKYELLOW=$'\033[33;2m'
C_GRAY=$'\033[90m'; C_WHITE=$'\033[97m'

say()  { printf '%s%s%s\n' "${2:-$C_WHITE}" "$1" "$C_RESET"; }
warn() { say "$1" "$C_YELLOW"; }
have() { command -v "$1" >/dev/null 2>&1; }

usage() { sed -n '2,26p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; }

# ---------------------------------------------------------------- arguments --
Port=""
Verbose=0
while [[ $# -gt 0 ]]; do
    case "$1" in
        -P|--port) Port="${2:-}"; shift 2 ;;
        -v|--verbose) Verbose=1; shift ;;
        -h|--help) usage; exit 0 ;;
        *) warn "Unknown option: $1"; usage; exit 1 ;;
    esac
done

# ------------------------------------------------------------ tool discovery --
SSH_BIN="$(command -v ssh || true)"
SFTP_BIN="$(command -v sftp || true)"
SSHPASS_BIN="$(command -v sshpass || true)"

[[ -n "$SSHPASS_BIN" ]] || warn "sshpass not found. ssh/sftp will prompt for the password instead of auto-filling."

# --------------------------------------------------------------- clipboard  --
copy_to_clipboard() {
    if have wl-copy;   then printf '%s' "$1" | wl-copy 2>/dev/null && return 0; fi
    if have xclip;     then printf '%s' "$1" | xclip -selection clipboard 2>/dev/null && return 0; fi
    if have xsel;      then printf '%s' "$1" | xsel --clipboard --input 2>/dev/null && return 0; fi
    if have pbcopy;    then printf '%s' "$1" | pbcopy 2>/dev/null && return 0; fi
    return 1
}

open_portal() {
    warn "Opening password portal..."
    if have xdg-open; then
        nohup xdg-open "$PORTAL_URL" >/dev/null 2>&1 &
    else
        say "  $PORTAL_URL" "$C_GRAY"
    fi
}

# -------------------------------------------------------------------- state --
declare -A STATIC_USER=()
declare -A STATIC_PASS=()
savedTermChoice="1"
savedFtChoice="0"
Username="4690"
Password=""
lastEnvironment="mc"
lastStore=""
PwdDate=""

obfuscate()   { printf '%s' "$1" | base64 | tr -d '\n'; }
deobfuscate() { printf '%s' "$1" | base64 -d 2>/dev/null; }

# --------------------------------------------------------------- config i/o --
save_config() {
    if [[ "$lastStore" =~ ^([a-zA-Z]{2,})\.([a-zA-Z]{2}[0-9]{3})$ ]]; then
        lastEnvironment="${BASH_REMATCH[1],,}"
        lastStore="${BASH_REMATCH[2]}"
    fi
    local tmp="$CONFIG_PATH.$$.tmp"
    umask 077
    {
        printf 'TermChoice=%s\n'      "$savedTermChoice"
        printf 'FtChoice=%s\n'        "$savedFtChoice"
        printf 'FtChoiceVersion=2\n'
        printf 'Port=%s\n'            "$Port"
        printf 'Username=%s\n'        "$Username"
        printf 'PwdEncoded=%s\n'      "$(obfuscate "$Password")"
        printf 'PwdDate=%s\n'         "$PwdDate"
        printf 'LastStore=%s\n'       "$lastStore"
        printf 'LastEnvironment=%s\n' "$lastEnvironment"
        local store
        for store in $(printf '%s\n' "${!STATIC_USER[@]}" | sort); do
            printf 'Static_%s_Username=%s\n' "$store" "${STATIC_USER[$store]}"
            printf 'Static_%s_Password=%s\n' "$store" "$(obfuscate "${STATIC_PASS[$store]:-}")"
        done
    } > "$tmp" && mv -f "$tmp" "$CONFIG_PATH"
    rm -f "$tmp"
    chmod 600 "$CONFIG_PATH" 2>/dev/null
}

load_config() {
    [[ -f "$CONFIG_PATH" ]] || return 0
    local key value pwdEncoded="" cfgPort="" ftChoiceVersion="" store
    while IFS= read -r line; do
        [[ -z "$line" || "$line" == \#* || "$line" != *=* ]] && continue
        key="${line%%=*}"; value="${line#*=}"
        case "$key" in
            TermChoice)      savedTermChoice="$value" ;;
            FtChoice)        savedFtChoice="$value" ;;
            FtChoiceVersion) ftChoiceVersion="$value" ;;
            Port)            cfgPort="$value" ;;
            Username)        Username="$value" ;;
            LastStore)       lastStore="$value" ;;
            LastEnvironment) lastEnvironment="$value" ;;
            PwdEncoded)      pwdEncoded="$value" ;;
            PwdDate)         PwdDate="$value" ;;
            Static_*_Username)
                store="${key#Static_}"; store="${store%_Username}"
                STATIC_USER["${store,,}"]="$value" ;;
            Static_*_Password)
                store="${key#Static_}"; store="${store%_Password}"
                STATIC_PASS["${store,,}"]="$(deobfuscate "$value")" ;;
        esac
    done < "$CONFIG_PATH"

    if [[ "$lastStore" =~ ^([a-zA-Z]{2,})\.([a-zA-Z]{2}[0-9]{3})$ ]]; then
        lastEnvironment="${BASH_REMATCH[1],,}"
        lastStore="${BASH_REMATCH[2]}"
    fi

    if [[ "$ftChoiceVersion" != "2" ]]; then
        case "$savedFtChoice" in
            1) savedFtChoice="0" ;;
            2) savedFtChoice="1" ;;
        esac
    fi

    # Command-line port takes precedence; fall back to config, then default 22
    [[ -z "$Port" ]] && Port="${cfgPort:-}"

    if [[ -n "$pwdEncoded" ]]; then
        Password="$(deobfuscate "$pwdEncoded")"
        say "Using saved credentials for $Username${PwdDate:+ (saved $PwdDate)}." "$C_GREEN"
    fi
}

# --------------------------------------------------------------- credential --
request_password() {
    local pw=""
    while [[ -z "$pw" ]]; do
        read -rsp "Enter password: " pw < /dev/tty; echo
        [[ -z "$pw" ]] && warn "Password cannot be empty. Please try again."
    done
    printf '%s' "$pw"
}

request_credentials() {
    local u
    read -rp "Enter username [default: 4690]: " u < /dev/tty
    Username="${u:-4690}"
    Password="$(request_password)"
    PwdDate="$(date +%F)"
}

# ------------------------------------------------------------------ launch  --
# ssh/sftp read the password from SSHPASS so it never appears in the process list.
run_with_password() {
    local pass="$1"; shift
    if [[ -n "$SSHPASS_BIN" ]]; then
        SSHPASS="$pass" "$SSHPASS_BIN" -e "$@"
    else
        "$@"
    fi
}

launch_bg() { nohup "$@" >/dev/null 2>&1 & disown; }

# Terminal emulator used for new ssh windows; TERMINAL_CMD overrides detection.
find_terminal() {
    local t p
    for t in ${TERMINAL_CMD:-} x-terminal-emulator gnome-terminal konsole xfce4-terminal \
             tilix kitty alacritty wezterm terminator mate-terminal lxterminal xterm; do
        if p="$(command -v "$t")"; then
            # x-terminal-emulator is an alternatives symlink; resolve it to the real emulator
            readlink -f "$p" 2>/dev/null || printf '%s' "$p"
            return 0
        fi
    done
    return 1
}

# Run a shell command line in a new terminal window; falls back to the current one.
run_in_new_terminal() {
    local title="$1" cmdline="$2" term
    term="$(find_terminal)" || {
        warn "No terminal emulator found - running in this window."
        bash -c "$cmdline"
        return
    }
    cmdline+='; echo; read -n1 -rsp "Session closed - press any key to close..."'
    case "$(basename "$term")" in
        gnome-terminal|tilix|mate-terminal)
            launch_bg "$term" --title="$title" -- bash -c "$cmdline" ;;
        konsole)
            launch_bg "$term" -p "tabtitle=$title" -e bash -c "$cmdline" ;;
        kitty|alacritty|wezterm)
            launch_bg "$term" -e bash -c "$cmdline" ;;
        *)
            launch_bg "$term" -T "$title" -e bash -c "$cmdline" ;;
    esac
}

# ------------------------------------------------------------------- start  --
load_config
[[ -z "$Port" ]] && Port="22"
SftpPort="$Port"

if [[ -z "$Password" ]]; then
    request_credentials
fi

firstRun=1
while true; do
    if [[ $firstRun -eq 1 ]]; then
        termChoice="$savedTermChoice"
        ftChoice="$savedFtChoice"
        firstRun=0
    else
        say $'\nTerminal session:' "$C_CYAN"
        say "0. None"; say "1. ssh (native)"
        read -rp "Select terminal (0-1) [default: $savedTermChoice]: " termChoice < /dev/tty
        termChoice="${termChoice:-$savedTermChoice}"

        say $'\nFile transfer session:' "$C_CYAN"
        say "0. None"; say "1. sftp (native)"
        read -rp "Select file transfer (0-1) [default: $savedFtChoice]: " ftChoice < /dev/tty
        ftChoice="${ftChoice:-$savedFtChoice}"

        read -rp "SSH/SFTP port [default: $Port]: " newPort < /dev/tty
        [[ -n "$newPort" ]] && Port="$newPort"
        SftpPort="$Port"

        savedTermChoice="$termChoice"
        savedFtChoice="$ftChoice"
        save_config

        local_state=$([[ $Verbose -eq 1 ]] && echo ON || echo OFF)
        read -rp "Verbose mode (shows launch commands) [current: $local_state] - Enter to keep, or 'on'/'off': " vt < /dev/tty
        [[ "$vt" == "on"  ]] && Verbose=1
        [[ "$vt" == "off" ]] && Verbose=0
    fi

    useSsh=0; useSftp=0
    [[ "$termChoice" == "1" ]] && useSsh=1
    [[ "$ftChoice"   == "1" ]] && useSftp=1

    if [[ $useSsh -eq 1 && -z "$SSH_BIN" ]]; then
        warn "ssh not found. Terminal will not be launched."; useSsh=0
    fi
    if [[ $useSftp -eq 1 && -z "$SFTP_BIN" ]]; then
        warn "sftp not found. File transfer will not be launched."; useSftp=0
    fi

    termName="None"; [[ $useSsh -eq 1 ]] && termName="ssh"
    ftName="None";   [[ $useSftp -eq 1 ]] && ftName="sftp"
    vState=$([[ $Verbose -eq 1 ]] && echo ON || echo OFF)
    say $'\n'"Active: Terminal=$termName  FileTransfer=$ftName  Port=$Port  Verbose=$vState" "$C_DKCYAN"

    # ------------------------------------------------------ connection loop --
    backToTools=0
    while true; do
        say $'\n--- New Connection ---' "$C_CYAN"
        say "  Endpoint: $lastEnvironment  |  'u' = usage  |  'x' = exit" "$C_GRAY"

        storePrompt="Store (e.g., ci123 / fc.ci123 / cc / FQDN / IP)"
        [[ -n "$lastStore" ]] && storePrompt+=" [default: $lastEnvironment.$lastStore]"
        read -rp "$storePrompt: " storeInput < /dev/tty
        storeInput="${storeInput#"${storeInput%%[![:space:]]*}"}"
        storeInput="${storeInput%"${storeInput##*[![:space:]]}"}"

        if [[ "$storeInput" == "u" ]]; then
            say $'\nStore commands:' "$C_CYAN"
            say "  s <host>  Launch ssh"
            say "  w <host>  Launch sftp"
            say "  t         Change tools"
            say "  c         Credential management"
            say "  e         Change endpoint"
            say "  x         Exit"
            continue
        fi
        if [[ "$storeInput" == "t" ]]; then backToTools=1; break; fi
        if [[ "$storeInput" == "x" ]]; then exit 0; fi

        if [[ "$storeInput" =~ ^f([[:space:]]|$) ]]; then
            warn "Unsupported tool command. Enter 'u' to see available commands."
            continue
        fi

        singleTool=""
        if [[ "$storeInput" =~ ^(s|w)([[:space:]]+(.+))?$ ]]; then
            singleTool="${BASH_REMATCH[1]}"
            if [[ -n "${BASH_REMATCH[3]:-}" ]]; then
                storeInput="${BASH_REMATCH[3]}"
            elif [[ -n "$lastStore" ]]; then
                storeInput="$lastStore"
            else
                warn "No default host is available. Enter a host after '$singleTool'."
                continue
            fi
        fi

        # ------------------------------------------ credential management --
        if [[ "$storeInput" == "c" ]]; then
            while true; do
                say $'\nCredential Management:' "$C_CYAN"
                say "1. Update daily password (PWD)"
                say "2. Copy current password to clipboard"
                say "3. Add/update static credentials for a store"
                say "4. Remove static credentials for a store"
                say "5. List stores with static credentials"
                say "6. Open password portal"
                say "7. Exit"
                say "   Current PWD: $Username${PwdDate:+ (set $PwdDate)}" "$C_GRAY"
                read -rp "Select (1-7): " credAction < /dev/tty
                case "$credAction" in
                    1)
                        request_credentials
                        save_config
                        say "Daily credentials updated." "$C_GREEN" ;;
                    2)
                        if [[ -n "$Password" ]] && copy_to_clipboard "$Password"; then
                            say "Current password copied to clipboard." "$C_GREEN"
                        else
                            warn "No password loaded, or no clipboard tool (install xclip/xsel/wl-clipboard)."
                        fi
                        break ;;
                    3)
                        read -rp "Enter store number to set static credentials for: " storeKey < /dev/tty
                        storeKey="${storeKey,,}"
                        if [[ -n "$storeKey" ]]; then
                            read -rp "Enter username for $storeKey [default: $Username]: " staticUser < /dev/tty
                            STATIC_USER["$storeKey"]="${staticUser:-$Username}"
                            STATIC_PASS["$storeKey"]="$(request_password)"
                            save_config
                            say "Static credentials saved for $storeKey." "$C_GREEN"
                        fi ;;
                    4)
                        read -rp "Enter store number to remove: " storeKey < /dev/tty
                        storeKey="${storeKey,,}"
                        if [[ -n "${STATIC_USER[$storeKey]:-}" ]]; then
                            unset 'STATIC_USER[$storeKey]' 'STATIC_PASS[$storeKey]'
                            save_config
                            say "Static credentials removed for $storeKey." "$C_GREEN"
                        else
                            warn "No static credentials found for '$storeKey'."
                        fi ;;
                    5)
                        if [[ ${#STATIC_USER[@]} -eq 0 ]]; then
                            warn "No static credentials stored."
                        else
                            say "Stores with static credentials:" "$C_CYAN"
                            for store in $(printf '%s\n' "${!STATIC_USER[@]}" | sort); do
                                say "  $store  (user: ${STATIC_USER[$store]})"
                            done
                        fi ;;
                    6) open_portal ;;
                    7) break ;;
                esac
            done
            continue
        fi

        if [[ "$storeInput" == "e" ]]; then
            read -rp "Enter endpoint (mc, cc, fc, etc.) [default: $lastEnvironment]: " newEnv < /dev/tty
            [[ -n "$newEnv" ]] && lastEnvironment="$newEnv"
            save_config
            continue
        fi

        if [[ "$storeInput" =~ ^([a-zA-Z]{2,})\.([a-zA-Z]{2}[0-9]{3})$ ]]; then
            Store="${BASH_REMATCH[2]}"
            Environment="${BASH_REMATCH[1],,}"
            lastStore="$Store"
            lastEnvironment="$Environment"
        elif [[ -n "$lastStore" && "$storeInput" =~ ^[a-zA-Z]{2}$ ]]; then
            Store="$lastStore"
            Environment="${storeInput,,}"
        else
            Environment="$lastEnvironment"
            Store="$storeInput"
            if [[ -z "$Store" ]]; then
                if [[ -n "$lastStore" ]]; then
                    Store="$lastStore"
                else
                    warn "Store number cannot be empty. Please try again."
                    continue
                fi
            fi
            if [[ "$storeInput" =~ ^[a-zA-Z]{2}[0-9]{3}$ ]]; then
                Environment="mc"
                lastEnvironment="$Environment"
            fi
            lastStore="$Store"
        fi

        launchSsh=$useSsh
        launchSftp=$useSftp
        if [[ -n "$singleTool" ]]; then
            launchSsh=0; launchSftp=0
            case "$singleTool" in
                s) launchSsh=1;       requestedBin="$SSH_BIN" ;;
                w) launchSftp=1;      requestedBin="$SFTP_BIN" ;;
            esac
            if [[ -z "$requestedBin" ]]; then
                warn "Requested tool is not installed or was not found."
                continue
            fi
        fi

        # Construct target host:
        # 2 letters + 3 digits    -> <endpoint>.<store>.kroger.com
        # endpoint.store form     -> <entry>.kroger.com
        # anything else           -> used directly as hostname or IP
        if [[ "$Store" =~ ^[a-zA-Z]{2}[0-9]{3}$ ]]; then
            TargetHost="$Environment.$Store.kroger.com"
        elif [[ "$Store" =~ ^[a-zA-Z]{2,}\.[a-zA-Z]{2}[0-9]{3}$ ]]; then
            TargetHost="$Store.kroger.com"
        else
            TargetHost="$Store"
            say "Non-standard entry - connecting directly to: $TargetHost" "$C_DKYELLOW"
        fi

        save_config

        # Tuna endpoint passes the current user ID only (no password); sftp is not supported
        noCreds=0
        if [[ "$Environment" == "tuna" || "$TargetHost" == tuna.* ]]; then
            noCreds=1
            if [[ $launchSftp -eq 1 ]]; then
                warn "sftp is not supported for tuna - skipping."
                launchSftp=0
            fi
        fi

        storeKey="${Store,,}"
        if [[ $noCreds -eq 1 ]]; then
            ConnUsername="$(id -un)"; ConnUsername="${ConnUsername,,}"
            ConnPassword=""
            say "Connecting to: $TargetHost as $ConnUsername  [USER ID only - tuna]" "$C_GREEN"
        elif [[ -n "${STATIC_PASS[$storeKey]:-}" ]]; then
            ConnUsername="${STATIC_USER[$storeKey]}"
            ConnPassword="${STATIC_PASS[$storeKey]}"
            say "Connecting to: $TargetHost as $ConnUsername  [STATIC credentials]" "$C_GREEN"
        else
            ConnUsername="$Username"
            ConnPassword="$Password"
            say "Connecting to: $TargetHost as $ConnUsername  [PWD credentials]" "$C_GREEN"
        fi

        if [[ $noCreds -eq 0 ]] && copy_to_clipboard "$ConnPassword"; then
            say "Password copied to clipboard." "$C_GREEN"
        fi

        if [[ $launchSsh -eq 1 ]]; then
            say "Launching ssh in a new terminal..." "$C_CYAN"
            if [[ $noCreds -eq 1 ]]; then
                [[ $Verbose -eq 1 ]] && say "  CMD: ssh -p $Port $ConnUsername@$TargetHost" "$C_DKYELLOW"
                sshCmd="$(printf 'ssh -p %q -o StrictHostKeyChecking=accept-new %q' \
                    "$Port" "$ConnUsername@$TargetHost")"
                run_in_new_terminal "$ConnUsername@$TargetHost" "$sshCmd"
            else
                [[ $Verbose -eq 1 ]] && say "  CMD: ssh -p $Port $ConnUsername@$TargetHost (password via SSHPASS)" "$C_DKYELLOW"
                sshCmd="$(printf 'ssh -p %q -o StrictHostKeyChecking=accept-new -o PubkeyAuthentication=no %q' \
                    "$Port" "$ConnUsername@$TargetHost")"
                [[ -n "$SSHPASS_BIN" ]] && sshCmd="$(printf '%q -e ' "$SSHPASS_BIN")$sshCmd"
                SSHPASS="$ConnPassword" run_in_new_terminal "$ConnUsername@$TargetHost" "$sshCmd"
            fi
        fi

        if [[ $launchSftp -eq 1 ]]; then
            say "Launching sftp..." "$C_CYAN"
            [[ $Verbose -eq 1 ]] && say "  CMD: sftp -P $SftpPort $ConnUsername@$TargetHost (password via SSHPASS)" "$C_DKYELLOW"
            run_with_password "$ConnPassword" "$SFTP_BIN" -P "$SftpPort" \
                -o StrictHostKeyChecking=accept-new -o PubkeyAuthentication=no \
                "$ConnUsername@$TargetHost"
        fi

        if [[ $launchSsh -eq 1 || $launchSftp -eq 1 ]]; then
            warn "Session(s) closed. Ready for next connection."
        fi
    done
    [[ $backToTools -eq 1 ]] && continue
done
