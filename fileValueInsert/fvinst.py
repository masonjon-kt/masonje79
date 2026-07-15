#!/usr/bin/env python3
"""
fvinst.py - File Value Insert/Replace/Delete utility

Usage:
  fvinst.py --file <file> --insert <value>                  # append value
  fvinst.py --file <file> --search <pattern> --insert <value>  # replace match
  fvinst.py --file <file> --search <pattern> --delete           # delete match

Options:
  --file      Target file path (required)
  --insert    Value to insert into the file
  --search    Search pattern (supports wildcards: *, ?, [seq]); required with --delete
  --create    Create the file if it does not exist (true/false)
  --delete    Delete lines matching the search pattern (requires --search)
"""
import argparse
import fnmatch
import os
import sys


def match_line(pattern, line):
    """Return True if the line matches the wildcard pattern."""
    return fnmatch.fnmatch(line.strip(), pattern)


def process_file(file_path, search_pattern, insert_value, create, delete):
    if not os.path.exists(file_path):
        if create:
            open(file_path, 'w').close()
            print(f"Created file: {file_path}")
        else:
            print(f"Error: target file not found: {file_path}", file=sys.stderr)
            sys.exit(1)

    with open(file_path, 'r') as f:
        lines = f.readlines()

    # No search pattern — plain append if value not already present
    if search_pattern is None:
        if insert_value is not None:
            existing = [l.strip() for l in lines]
            if insert_value in existing:
                print(f"Value already exists in file: {insert_value}")
            else:
                with open(file_path, 'a') as f:
                    if lines and not lines[-1].endswith('\n'):
                        f.write('\n')
                    f.write(insert_value + '\n')
                print(f"Inserted: {insert_value}")
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
                new_lines.append(insert_value + '\n')
                continue
        new_lines.append(line)

    if already_exact and matched_count == 0:
        print(f"Value already exists in file: {insert_value}")
        return

    if matched_count == 0 and not delete:
        if insert_value is not None:
            # No match found — insert the value as a new line
            if new_lines and not new_lines[-1].endswith('\n'):
                new_lines.append('\n')
            new_lines.append(insert_value + '\n')
            print(f"No match found for '{search_pattern}'. Inserted: {insert_value}")
        else:
            print(f"No match found for '{search_pattern}'. Nothing changed.")
        with open(file_path, 'w') as f:
            f.writelines(new_lines)
        return

    with open(file_path, 'w') as f:
        f.writelines(new_lines)

    if delete:
        print(f"Deleted {matched_count} line(s) matching '{search_pattern}'.")
    else:
        print(f"Replaced {matched_count} line(s) matching '{search_pattern}' with: {insert_value}")


def main():
    parser = argparse.ArgumentParser(
        description="Insert, replace, or delete lines in a file using wildcard search patterns."
    )
    parser.add_argument("--file", required=True, help="Target file path")
    parser.add_argument("--search", default=None, help="Search pattern (supports wildcards: *, ?, [seq]). Required with --delete.")
    parser.add_argument(
        "--insert",
        default=None,
        help="Value to insert into the file. Inserted if no match found; replaces matching lines if found. Omit when using --delete.",
    )
    parser.add_argument(
        "--create",
        type=lambda x: x.lower() in ("true", "1", "yes"),
        default=False,
        metavar="true|false",
        help="Create the file if it does not exist (true/false)",
    )
    parser.add_argument(
        "--delete",
        action="store_true",
        help="Delete lines matching the search pattern instead of replacing them",
    )

    args = parser.parse_args()

    if args.delete and args.insert is not None:
        parser.error("--delete cannot be used together with --insert.")
    if args.delete and args.search is None:
        parser.error("--delete requires --search.")
    if args.search is not None and args.insert is None and not args.delete:
        parser.error("--search requires either --insert or --delete.")

    process_file(args.file, args.search, args.insert, args.create, args.delete)


if __name__ == "__main__":
    main()
