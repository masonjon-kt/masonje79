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

### Append a value (only if not already present)

```bash
# Appends "MYVALUE" to the end of the file if it doesn't already exist
python3 fvinst.py -f ./config.txt -i "MYVALUE"
```

### Replace lines matching a pattern

```bash
# Replaces any line matching "HOST=*" with "HOST=newserver"
python3 fvinst.py -f ./config.txt -s "HOST=*" -i "HOST=newserver"

# Replace a line matching a prefix pattern
python3 fvinst.py -f ./settings.txt -s "timeout=*" -i "timeout=30"
```

### Replace only if matched — no append on no match

```bash
# Updates the PORT line only if it exists; does nothing if not found
python3 fvinst.py -f ./config.txt -s "PORT=*" -i "PORT=8080" -se
```

### Delete matching lines

```bash
# Deletes all lines matching "DEBUG=*"
python3 fvinst.py -f ./config.txt -s "DEBUG=*" -d

# Delete a specific exact line
python3 fvinst.py -f ./config.txt -s "REMOVE_THIS_LINE" -d
```

### Search only (no file changes)

```bash
# Exit 0 if found, -1 if not found — useful in scripts
python3 fvinst.py -f ./config.txt -s "HOST=*" -so
if [ $? -eq 0 ]; then echo "HOST entry exists"; fi

# Search for an exact value
python3 fvinst.py -f ./config.txt -s "MYVALUE" -so
```

### Create file if it doesn't exist, then insert

```bash
# Creates config.txt if missing, then appends the value
python3 fvinst.py -f ./config.txt -i "HOST=myserver" -c true
```

### Wildcard patterns

```bash
# Match any line starting with "server."
python3 fvinst.py -f ./hosts.txt -s "server.*" -d

# Match lines with exactly 3 characters
python3 fvinst.py -f ./codes.txt -s "???" -so

# Match a literal asterisk in the line
python3 fvinst.py -f ./file.txt -s "prefix[*]suffix" -so
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
