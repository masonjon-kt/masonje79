#!/usr/bin/env python3
"""
fvinst.py - File Value Insert/Replace/Delete utility

Usage:
    fvinst.py -f <file> -i <value>                           # append value if not present
    fvinst.py -f <file> -s <pattern> -i <value>              # replace matching line(s)
    fvinst.py -f <file> -s <pattern> -d                       # delete matching line(s)
    fvinst.py -f <file> -i <value> -c true                    # create file then insert

Options:
    -f, --file      Target file path (required)
    -i, --insert    Value to insert into the file
    -s, --search    Search pattern (supports wildcards: *, ?, [seq]); required with --delete
    -c, --create    Create the file if it does not exist (true/false); cannot be used with --delete
    -d, --delete    Delete lines matching the search pattern (requires --search; cannot be used with --insert)
    -v, --debug     Enable verbose debug output

Exit codes:
  0  Success
  1  Target file not found and --create is not true
  2  File could not be created
  3  File could not be read
  4  File could not be written
"""
import argparse
import fnmatch
import os
import sys

try:
    from os4690 import mappath
    issky = True
except ImportError:
    issky = False

_debug = False

def std_out(level, message):
    """Central output manager. Levels: 'info', 'debug', 'error'."""
    if level == 'debug':
        if _debug:
            print(f"[DEBUG] {message}")
    elif level == 'error':
        print(f"[ERROR] {message}", file=sys.stderr)
    else:
        print(message)
    
def match_line(pattern, line):
    """Return True if the line matches the wildcard pattern."""
    return fnmatch.fnmatch(line.strip(), pattern)


def detect_eol(file_path):
    """Return the EOL sequence used in the file ('\r\n' or '\n').
    Reads raw bytes so EOL is never translated by Python's text mode."""
    try:
        with open(file_path, 'rb') as f:
            raw = f.read(4096)
        if b'\r\n' in raw:
            return '\r\n'
    except OSError:
        pass
    return '\n'


def process_file(file_path, search_pattern, insert_value, create, delete):
    std_out('debug', f"Processing file path: {file_path}")
    std_out('debug', f"Mode: delete={delete}, create={create}, has_search={search_pattern is not None}")

    if not os.path.exists(file_path):
        std_out('debug', "Target file does not exist.")
        if delete:
            std_out('error', f"target file not found: {file_path}")
            sys.exit(1)
        if create:
            try:
                std_out('debug', "Create flag is true. Creating missing target file.")
                open(file_path, 'w').close()
                std_out('info', f"Created file: {file_path}")
            except OSError as e:
                std_out('error', f"could not create file '{file_path}': {e}")
                sys.exit(2)
        else:
            std_out('error', f"target file not found: {file_path}")
            sys.exit(1)

    try:
        std_out('debug', "Reading target file.")
        with open(file_path, 'r', newline='') as f:
            lines = f.readlines()
        eol = detect_eol(file_path)
        std_out('debug', f"Read {len(lines)} line(s) from file. EOL style: {repr(eol)}")
    except OSError as e:
        std_out('error', f"could not read file '{file_path}': {e}")
        sys.exit(3)

    # No search pattern — plain append if value not already present
    if search_pattern is None:
        std_out('debug', "No search pattern provided; insert-only mode.")
        if insert_value is not None:
            existing = [l.strip() for l in lines]
            if insert_value in existing:
                std_out('info', f"Value already exists in file: {insert_value}")
                std_out('debug', "Insert value already present. No file changes made.")
            else:
                try:
                    std_out('debug', "Appending insert value to end of file.")
                    with open(file_path, 'a', newline='') as f:
                        if lines and not lines[-1].endswith(('\n', '\r\n')):
                            f.write(eol)
                        f.write(insert_value + eol)
                    std_out('info', f"Inserted: {insert_value}")
                except OSError as e:
                    std_out('error', f"could not write to file '{file_path}': {e}")
                    sys.exit(4)
        return

    new_lines = []
    matched_count = 0
    already_exact = False

    for line in lines:
        if match_line(search_pattern, line):
            if insert_value is not None and line.strip() == insert_value.strip():
                # Line already matches insert value exactly — leave unchanged
                already_exact = True
                new_lines.append(line)
                continue
            matched_count += 1
            if delete:
                # Skip line (effectively deletes it)
                continue
            elif insert_value is not None:
                new_lines.append(insert_value + eol)
                continue
        new_lines.append(line)

    std_out('debug', f"Matched {matched_count} line(s); exact-match skips: {already_exact}.")

    if already_exact and matched_count == 0:
        std_out('info', f"Value already exists in file: {insert_value}")
        return

    if delete and matched_count == 0:
        std_out('info', f"No matches found for '{search_pattern}'. Nothing deleted.")
        std_out('debug', "Delete requested but no matches found. No file changes made.")
        return

    if matched_count == 0 and not delete:
        if insert_value is not None:
            # No match found — insert the value as a new line
            if new_lines and not new_lines[-1].endswith(('\n', '\r\n')):
                new_lines.append(eol)
            new_lines.append(insert_value + eol)
            std_out('info', f"No match found for '{search_pattern}'. Inserted: {insert_value}")
        else:
            std_out('info', f"No match found for '{search_pattern}'. Nothing changed.")
        try:
            std_out('debug', "Writing updated content after no-match insert behavior.")
            with open(file_path, 'w', newline='') as f:
                f.writelines(new_lines)
        except OSError as e:
            std_out('error', f"could not write to file '{file_path}': {e}")
            sys.exit(4)
        return

    try:
        std_out('debug', "Writing updated content after replace/delete operation.")
        with open(file_path, 'w', newline='') as f:
            f.writelines(new_lines)
    except OSError as e:
        std_out('error', f"could not write to file '{file_path}': {e}")
        sys.exit(4)

    if delete:
        std_out('info', f"Deleted {matched_count} line(s) matching '{search_pattern}'.")
    else:
        std_out('info', f"Replaced {matched_count} line(s) matching '{search_pattern}' with: {insert_value}")


def main():
    parser = argparse.ArgumentParser(
        description="Insert, replace, or delete lines in a file using wildcard search patterns.",
        epilog=(
            "Exit codes:\n"
            "  0  Success\n"
            "  1  Target file not found and --create is not true\n"
            "  2  File could not be created\n"
            "  3  File could not be read\n"
            "  4  File could not be written"
        ),
        formatter_class=argparse.RawDescriptionHelpFormatter,
    )
    parser.add_argument("-f", "--file", required=True, help="Target file path")
    parser.add_argument("-s", "--search", default=None, help="Search pattern (supports wildcards: *, ?, [seq]). Required with --delete.")
    parser.add_argument(
        "-i",
        "--insert",
        default=None,
        help="Value to insert into the file. Inserted if no match found; replaces matching lines if found. Omit when using --delete.",
    )
    parser.add_argument(
        "-c",
        "--create",
        type=lambda x: x.lower() in ("true", "1", "yes"),
        default=False,
        metavar="true|false",
        help="Create the file if it does not exist (true/false)",
    )
    parser.add_argument(
        "-d",
        "--delete",
        action="store_true",
        help="Delete lines matching the search pattern instead of replacing them",
    )
    parser.add_argument(
        "-v",
        "--debug",
        action="store_true",
        help="Enable verbose debug output",
    )

    args = parser.parse_args()

    if args.delete and args.insert is not None:
        parser.error("--delete cannot be used together with --insert.")
    if args.delete and args.create:
        parser.error("--delete cannot be used together with --create.")
    if args.delete and args.search is None:
        parser.error("--delete requires --search.")
    if args.search is not None and args.insert is None and not args.delete:
        parser.error("--search requires either --insert or --delete.")

    global _debug
    _debug = args.debug
    std_out('debug', f"Sky runtime detected: {issky}")
    if issky:
        std_out('debug', f"Mapping Sky path with os4690.mappath: {args.file}")
        filePath = mappath(args.file, False)
        std_out('debug', f"Mapped file path: {filePath}")
    else:
        filePath = args.file
        std_out('debug', f"Using file path without mapping: {filePath}")

    process_file(filePath, args.search, args.insert, args.create, args.delete)


if __name__ == "__main__":
    main()
