# fvinst.py — File Value Insert/Replace/Delete Utility

A command-line utility for inserting, replacing, and deleting lines in plain text files using wildcard search patterns. Designed for use on standard systems and IBM 4690/Sky OS controllers.

## Requirements

- Python 3.6+
- No third-party packages required
- On 4690/Sky: `os4690` module (auto-detected; path mapping applied automatically)

---

## Features

- Append a value to a file if it isn't already present
- Replace lines matching a wildcard pattern
- Delete lines matching a wildcard pattern
- Search-only mode (no file changes, scriptable exit codes)
- Search-exclusive mode: replace only on match, never append on no match
- Auto-create file if it doesn't exist (`-c true`)
- Automatic EOL detection — preserves `\r\n` or `\n` style of the source file
- Handles files missing a final carriage return correctly
- Sky/4690 path mapping via `os4690.mappath` (auto-detected at startup)

---

## Command-Line Usage

```
python3 fvinst.py -f <file> [options]
```

### Options

| Flag | Description |
|------|-------------|
| `-f`, `--file` | Target file path (required) |
| `-i`, `--insert` | Value to insert or use as replacement |
| `-s`, `--search` | Wildcard search pattern. Supports `*`, `?`, `[seq]`. To match literal `*`, `?`, `[`, wrap in brackets: `[*]`, `[?]`, `[[]` |
| `-c true` | Create the file if it does not exist |
| `-d`, `--delete` | Delete lines matching `-s` (requires `--search`) |
| `-se`, `--search-exclusive` | With `-s` and `-i`: replace on match only; do not append if no match found |
| `-so`, `--search-only` | Search only; no file changes. Exit 0 if found, -1 if not found |
| `-v`, `--debug` | Enable verbose debug output |

### Exit Codes

| Code | Meaning |
|------|---------|
| 0 | Success / pattern found |
| -1 | Pattern not found (search-only mode) |
| 1 | Target file not found and `--create` is not true |
| 2 | File could not be created |
| 3 | File could not be read |
| 4 | File could not be written |

---

## Examples

All examples are written for Windows `.bat` files.

### Append a value (only if not already present)

```bat
python3 C:\adx_spgm\fvinst.py -f C:\adx_upgm\adxcfg.dat -i "MYVALUE"
IF %ERRORLEVEL% NEQ 0 GOTO :ERROR
```

---

### Replace lines matching a pattern

```bat
REM Replace any line matching "HOST=*" with "HOST=newserver"
python3 C:\adx_spgm\fvinst.py -f C:\adx_upgm\adxcfg.dat -s "HOST=*" -i "HOST=newserver"
IF %ERRORLEVEL% NEQ 0 GOTO :ERROR

REM Replace a timeout value
python3 C:\adx_spgm\fvinst.py -f C:\adx_upgm\adxcfg.dat -s "timeout=*" -i "timeout=30"
IF %ERRORLEVEL% NEQ 0 GOTO :ERROR
```

---

### Replace only if matched — no append on no match

```bat
REM Updates PORT only if the line exists; does nothing if not found
python3 C:\adx_spgm\fvinst.py -f C:\adx_upgm\adxcfg.dat -s "PORT=*" -i "PORT=8080" -se
IF %ERRORLEVEL% NEQ 0 GOTO :ERROR
```

---

### Delete matching lines

```bat
REM Delete all lines matching "DEBUG=*"
python3 C:\adx_spgm\fvinst.py -f C:\adx_upgm\adxcfg.dat -s "DEBUG=*" -d
IF %ERRORLEVEL% NEQ 0 GOTO :ERROR

REM Delete a specific exact line
python3 C:\adx_spgm\fvinst.py -f C:\adx_upgm\adxcfg.dat -s "REMOVE_THIS_LINE" -d
IF %ERRORLEVEL% NEQ 0 GOTO :ERROR
```

---

### Search only (no file changes)

```bat
REM Check if HOST entry exists — exit 0 found, non-zero not found
python3 C:\adx_spgm\fvinst.py -f C:\adx_upgm\adxcfg.dat -s "HOST=*" -so
IF %ERRORLEVEL% NEQ 0 (
    ECHO HOST entry not found
    GOTO :NOT_FOUND
)
ECHO HOST entry exists
```

> **Note:** Search-only returns `-1` when not found. In a `.bat` file,
> `%ERRORLEVEL%` sees `-1` as a non-zero value, so `NEQ 0` catches it correctly.

---

### Create file if it doesn't exist, then insert

```bat
REM Creates the file if missing, then appends the value
python3 C:\adx_spgm\fvinst.py -f C:\adx_upgm\adxcfg.dat -i "HOST=myserver" -c true
IF %ERRORLEVEL% NEQ 0 GOTO :ERROR
```

---

### Wildcard patterns

```bat
REM Match any line starting with "server."
python3 C:\adx_spgm\fvinst.py -f C:\adx_upgm\adxcfg.dat -s "server.*" -d
IF %ERRORLEVEL% NEQ 0 GOTO :ERROR

REM Match lines with exactly 3 characters
python3 C:\adx_spgm\fvinst.py -f C:\adx_upgm\adxcfg.dat -s "???" -so
IF %ERRORLEVEL% NEQ 0 GOTO :NOT_FOUND

REM Match a literal asterisk in the line
python3 C:\adx_spgm\fvinst.py -f C:\adx_upgm\adxcfg.dat -s "prefix[*]suffix" -so
IF %ERRORLEVEL% NEQ 0 GOTO :NOT_FOUND
```

---

### Full example script with error handling

```bat
@ECHO OFF

REM Step 1: Ensure the config file exists with a HOST entry
python3 C:\adx_spgm\fvinst.py -f C:\adx_upgm\adxcfg.dat -i "HOST=myserver" -c true
IF %ERRORLEVEL% NEQ 0 GOTO :ERROR

REM Step 2: Replace the PORT value if it exists
python3 C:\adx_spgm\fvinst.py -f C:\adx_upgm\adxcfg.dat -s "PORT=*" -i "PORT=8080" -se
IF %ERRORLEVEL% NEQ 0 GOTO :ERROR

REM Step 3: Remove any DEBUG lines
python3 C:\adx_spgm\fvinst.py -f C:\adx_upgm\adxcfg.dat -s "DEBUG=*" -d
IF %ERRORLEVEL% NEQ 0 GOTO :ERROR

REM Step 4: Confirm HOST is present
python3 C:\adx_spgm\fvinst.py -f C:\adx_upgm\adxcfg.dat -s "HOST=*" -so
IF %ERRORLEVEL% NEQ 0 GOTO :NOT_FOUND

ECHO Configuration complete.
GOTO :EOF

:NOT_FOUND
ECHO Required entry not found in config. Aborting.
EXIT /B 1

:ERROR
ECHO fvinst.py failed with error code %ERRORLEVEL%.
EXIT /B %ERRORLEVEL%
```

---

## Behavior Details

### Duplicate detection
When using `-i` without `-s`, the value is only appended if it does not already exist as a line in the file (after stripping whitespace).

### EOL preservation
The script detects whether the file uses `\r\n` (Windows/DOS) or `\n` (Unix) line endings and writes all new/replaced lines using the same style.

### Missing final newline
If the last line of the file has no line ending, the script correctly appends a newline to that line before inserting new content — preventing the new line from concatenating onto the end of the last line.

### Search pattern matching
Patterns use Python's `fnmatch` (shell-style wildcards):

| Pattern | Matches |
|---------|---------|
| `*` | Any sequence of characters |
| `?` | Any single character |
| `[seq]` | Any character in seq |
| `[!seq]` | Any character not in seq |
| `[*]` | Literal `*` |
| `[?]` | Literal `?` |
| `[[]` | Literal `[` |

Matching is performed against the line with the trailing newline stripped.

---

## Sky / 4690 OS Support

When run on a 4690/Sky controller where the `os4690` module is available, the script:

1. Detects the Sky environment automatically at startup
2. Maps the `-f` file path through `os4690.mappath()` to resolve it to the correct host filesystem path
3. Sends error messages to stdout instead of stderr (Sky may not support stderr)

No changes to command syntax are needed — the path mapping is transparent.

---

## Script Behavior Summary

| Flags used | Behavior |
|------------|----------|
| `-f -i` | Append value if not already in file |
| `-f -s -i` | Replace matching lines; append if no match |
| `-f -s -i -se` | Replace matching lines only; do nothing if no match |
| `-f -s -d` | Delete all matching lines |
| `-f -s -so` | Search only; exit 0 found / -1 not found |
| `-f -i -c true` | Create file if missing, then append value |
