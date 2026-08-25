# PuTTY Environment Launcher

`puttystart.ps1` is an interactive PowerShell launcher for connecting to Kroger environments with PuTTY, TinyTerm, FileZilla, and WinSCP.

## Requirements

- Windows PowerShell or PowerShell 7 (`pwsh`)
- One or more supported tools installed:
  - PuTTY
  - TinyTerm
  - FileZilla
  - WinSCP
- Permission to run PowerShell scripts

The script looks for the applications in their usual `Program Files` and `Program Files (x86)` locations.

## Start the Script

Open PowerShell in this directory and run:

```powershell
.\puttystart.ps1
```

Optional parameters:

```powershell
.\puttystart.ps1 -v
```

`-v` displays the launch command before starting a tool. Passwords are masked in verbose output.

`-Port` changes the SSH and SFTP port. The default is `22`.

## First Startup

On startup, the script loads saved credentials and preferences from `puttystart.cfg` in the same directory as the script.

If a valid password saved today is available, it is reused. Otherwise, the script opens the password portal and prompts for credentials. The default username is `4690`.

The saved password is encrypted with PowerShell and can only be decrypted by the same Windows user account that created it.

## Tool Selection

On the first connection, the script uses the saved terminal and file-transfer selections. Use `t` from the store prompt to change those selections.

The tool-selection menu contains:

- Terminal: None, PuTTY, or TinyTerm
- File transfer: None, FileZilla, or WinSCP
- SSH/SFTP port
- TinyTerm template path when TinyTerm is selected
- Verbose mode

The selected tools are used for normal store connections. If both a terminal and file-transfer tool are selected, both are launched.

## Store Prompt

The store prompt accepts a store identifier, endpoint, hostname, or IP address.

Examples:

```text
ci123
fc.ci123
server01.example.com
10.20.30.40
```

For a normal store identifier such as `ci123`, the script builds a hostname using the current endpoint:

```text
mc.ci123.kroger.com
```

Use `e` to change the endpoint from the default `mc` to another value such as `cc` or `fc`.

## Store Commands

The prompt displays only the most commonly needed commands:

```text
'u' = usage
'x' = exit
```

Enter `u` to display the complete command menu:

```text
p <host>  Launch PuTTY
t <host>  Launch TinyTerm
f <host>  Launch FileZilla
w <host>  Launch WinSCP
t         Change tools
c         Credential management
e         Change endpoint
x         Exit
```

## Launch One Tool for One Host

Use a tool letter followed by a space and the target host:

```text
p mc.ci123
t server01.example.com
f 10.20.30.40
w host.example.com
```

The commands are:

- `p <host>` launches PuTTY only
- `t <host>` launches TinyTerm only
- `f <host>` launches FileZilla only
- `w <host>` launches WinSCP only

The host is optional. When it is omitted, the command uses the last store or host entered:

```text
p
t
f
w
```

If no previous host is available, enter the host explicitly after the tool letter.

For example:

```text
p mc.ci123
```

launches PuTTY for the resolved host `mc.ci123.kroger.com`, regardless of the normal saved tool selections.

A direct hostname or IP address is used as entered:

```text
p 10.20.30.40
w server01.example.com
```

The one-tool command does not change the saved tool selections. After the tool closes, the script returns to the store prompt.

## Credential Management

Enter `c` at the store prompt to open credential management.

Available actions:

1. Update the daily password and username
2. Copy the current password to the clipboard
3. Add or update static credentials for a store
4. Remove static credentials for a store
5. List stores with static credentials
6. Exit the credential menu

Static credentials override the daily credentials only for the matching store.

## Password Portal Behavior

The script treats a password as current only when the saved `PwdDate` matches the current date. When the date is expired, it opens the password portal and requests updated credentials.

The portal is opened at most once during startup, even when the saved password is expired and the later credential prompt is also required.

## Configuration File

The script creates `puttystart.cfg` beside `puttystart.ps1`. It stores preferences and encrypted password data, including:

- Terminal selection
- File-transfer selection
- Port
- TinyTerm template path
- Username
- Encrypted password
- Password date
- Last store
- Last endpoint
- Static store credentials

Do not edit the encrypted password fields manually. The script writes the configuration through a temporary file and replaces the active file after a complete write, which helps prevent an interrupted save from leaving a partial configuration.

## Common Examples

Start normally:

```powershell
.\puttystart.ps1
```

Start with verbose launch commands:

```powershell
.\puttystart.ps1 -v
```

Use a non-standard SSH/SFTP port:

```powershell
.\puttystart.ps1 -Port 2222
```

Then, at the store prompt, launch only PuTTY:

```text
p mc.ci123
```

Launch only WinSCP for a direct host:

```text
w 10.20.30.40
```

Show the command menu:

```text
u
```

Exit:

```text
x
```
