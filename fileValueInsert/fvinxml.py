#!/usr/bin/env python3
"""
fvinxml.py - XML File Value Insert/Update/Delete utility

Edits XML files using the ElementTree object model (no manual string parsing).

Usage:
    fvinxml.py -f <file> -p <xpath>                          # search only (exit 0 found, 4 not found)
    fvinxml.py -f <file> -p <xpath> -v <value>               # set element text
    fvinxml.py -f <file> -p <xpath> -a <attr> -v <value>     # set attribute value
    fvinxml.py -f <file> -p <xpath> -v <value> -c            # set element text, create path if missing
    fvinxml.py -f <file> -p <xpath> -a <attr> -v <value> -c  # set attribute, create element if missing
    fvinxml.py -f <file> -p <xpath> -d                       # delete element
    fvinxml.py -f <file> -p <xpath> -a <attr> -d             # delete attribute from element
    fvinxml.py -f <file> -p <xpath> --append <tag> [--set k=v ...]  # append new child element

Options:
    -f, --file        Target XML file path (required)
    -p, --path        XPath expression to the target element
                        Supports ElementTree XPath subset:
                          config/server/host         simple path
                          config/item[@name='foo']   attribute predicate
                          config/item[1]             index (1-based)
    -a, --attribute   Attribute name to get/set/delete on the matched element
    -v, --value       Value to set on element text or attribute
    -c, --create      Create missing elements along the path if they don't exist
    -d, --delete      Delete the matched element (or attribute if -a is given)
    --append <tag>    Append a new child element with this tag name under the element at -p.
                      Use --set to assign attributes. Skips append if identical element exists
                      unless --force is also given.
    --set key=value   One or more attribute assignments for the appended element.
                      Repeat for multiple: --set location=adx_spgm: --set suffix=jon.DAT
    --force           With --append, always append even if an identical element already exists.
    -so, --search-only
                      Search only; no file changes. Exit 0 if found, 4 if not found.
    -cf, --create-file
                      Create the XML file if it does not exist. The root element
                      is taken from the first segment of the --path argument.
    --debug           Enable verbose debug output

Exit codes:
    0   Success / element found
    1   Target file not found
    2   File could not be created or written
    3   File could not be read or parsed
    4   Element or attribute not found (and --create not set)
    5   Invalid arguments
    6   Written file failed XML validation; original restored from backup

Examples:

  # Add a new Controller block with Extensions for id='MM':
  python3 ./fvinxml.py -f ./contrext.xml -p "ControllerExtensions" --append Controller --set id="MM"
  python3 ./fvinxml.py -f ./contrext.xml -p "ControllerExtensions/Controller[@id='MM']" --append Extensions
  python3 ./fvinxml.py -f ./contrext.xml -p "ControllerExtensions/Controller[@id='MM']/Extensions" --append Extension --set location="adx_spgm:" suffix="ADXXTSJ8.DAT"
  python3 ./fvinxml.py -f ./contrext.xml -p "ControllerExtensions/Controller[@id='MM']/Extensions" --append Extension --set location="adx_spgm:" suffix="ADXXTSSH.DAT"
  python3 ./fvinxml.py -f ./contrext.xml -p "ControllerExtensions/Controller[@id='MM']/Extensions" --append Extension --set location="adx_spgm:" suffix="ADXXTSDK.DAT"

  # Delete a specific Extension entry (first match only):
  python3 ./fvinxml.py -f ./contrext.xml -p "ControllerExtensions/Controller[@id='MM']/Extensions/Extension[@suffix='ADXXTSDK.DAT']" -d

  # Delete ALL Extension entries matching a suffix (all duplicates at once):
  python3 ./fvinxml.py -f ./contrext.xml -p "ControllerExtensions/Controller[@id='MM']/Extensions/Extension[@suffix='ADXXTpoo.DAT']" -da

  # Delete an entire Controller block:
  python3 ./fvinxml.py -f ./contrext.xml -p "ControllerExtensions/Controller[@id='MM']" -d

  # Delete a specific attribute from an element:
  python3 ./fvinxml.py -f ./contrext.xml -p "ControllerExtensions/Controller[@id='MM']/Extensions/Extension[@suffix='ADXXTSDK.DAT']" -a location -d

  # Check if a Controller exists:
  python3 ./fvinxml.py -f ./contrext.xml -p "ControllerExtensions/Controller[@id='MM']"

  # Check if a specific Extension entry exists (by attribute value):
  python3 ./fvinxml.py -f ./contrext.xml -p "ControllerExtensions/Controller[@id='FC']/Extensions/Extension[@suffix='ADXXTSJ8.DAT']"

  # Check if an attribute exists on a specific element and show its value:
  python3 ./fvinxml.py -f ./contrext.xml -p "ControllerExtensions/Controller[@id='FC']/Extensions/Extension[@suffix='ADXXTSJ8.DAT']" -a location

  # Check if any Extension exists under a Controller (finds first match):
  python3 ./fvinxml.py -f ./contrext.xml -p "ControllerExtensions/Controller[@id='FC']/Extensions/Extension"

  # Check if an attribute exists on the root-level FileVersion element:
  python3 ./fvinxml.py -f ./contrext.xml -p "ControllerExtensions/FileVersion" -a version

  # Set an attribute on an existing element:
  python3 ./fvinxml.py -f ./contrext.xml -p "ControllerExtensions/FileVersion" -a version -v "v6r3"

  # Create a new XML file from scratch:
  python3 ./fvinxml.py -f ./new.xml -p "ControllerExtensions/Controller[@id='FC']" -cf -c
"""
import argparse
import os
import sys
import xml.etree.ElementTree as ET

try:
    from os4690 import mappath
    issky = True
except ImportError:
    issky = False

_debug = False


def dbg(msg):
    if _debug:
        print(f"[DEBUG] {msg}")


def err(msg):
    if issky:
        print(f"[ERROR] {msg}")  # Sky environment may not support sys.stderr
    else:
        print(f"[ERROR] {msg}", file=sys.stderr)


def strip_root_tag(root, xpath):
    """
    ElementTree.find() paths are relative to the element they're called on.
    If the user passes a full path like 'config/ext/some' and root is <config>,
    strip the leading 'config/' so the search is correctly relative to root.
    Also handles the case where xpath == root.tag (referring to root itself).
    """
    tag = root.tag
    if xpath == tag:
        return '.'
    if xpath.startswith(tag + '/'):
        stripped = xpath[len(tag) + 1:]
        dbg(f"Stripped root tag '{tag}' from path -> '{stripped}'")
        return stripped
    return xpath


def find_or_create(tree_root, xpath, create):
    """
    Locate element at xpath. If not found and create=True, build the missing
    elements. Supports predicated parents: finds the parent via full XPath,
    then creates only the final simple tag as a child.
    Returns the element, or None if not found and create=False.
    """
    xpath = strip_root_tag(tree_root, xpath)

    if xpath == '.':
        dbg("xpath refers to root element itself")
        return tree_root

    el = tree_root.find(xpath)
    if el is not None:
        dbg(f"Found element at xpath: {xpath}")
        return el

    if not create:
        dbg(f"Element not found at xpath: {xpath}")
        return None

    # Split into parent path and final child tag.
    # The final segment must be a plain tag name (no predicates).
    if '/' in xpath:
        parent_xpath, child_tag = xpath.rsplit('/', 1)
    else:
        parent_xpath = None
        child_tag = xpath

    # Final tag must not contain predicates or special chars
    import re as _re
    if _re.search(r'[\[\]@\*]', child_tag):
        err(f"Cannot auto-create element with complex final tag: '{child_tag}'")
        return None

    if parent_xpath:
        # Try to find parent — supports predicate paths like Controller[@ID='FC']
        parent = tree_root.find(parent_xpath)
        if parent is None:
            # Parent not found — try to create it if it's a plain path
            if _re.search(r'[\[\]@\*]', parent_xpath):
                err(f"Cannot auto-create parent — not found and path contains predicates: '{parent_xpath}'")
                return None
            dbg(f"Parent not found; creating plain path: {parent_xpath}")
            parts = parent_xpath.lstrip('./').split('/')
            current = tree_root
            for part in parts:
                child = current.find(part)
                if child is None:
                    dbg(f"  Creating element: <{part}>")
                    child = ET.SubElement(current, part)
                current = child
            parent = current
        else:
            dbg(f"Found parent at: {parent_xpath} -> <{parent.tag}>")
    else:
        parent = tree_root

    dbg(f"Creating child element <{child_tag}> under <{parent.tag}>")
    new_el = ET.SubElement(parent, child_tag)
    return new_el


def detect_doctype(file_path):
    """Scan file for a DOCTYPE declaration and return it as a string, or None."""
    try:
        with open(file_path, 'r', encoding='utf-8', errors='replace') as fh:
            for line in fh:
                stripped = line.strip()
                if stripped.startswith('<!DOCTYPE'):
                    dbg(f"Detected DOCTYPE: {stripped}")
                    return stripped
                # DOCTYPE must appear before the root element
                if stripped and not stripped.startswith('<?') and not stripped.startswith('<!--'):
                    break
    except OSError:
        pass
    return None


def write_xml(tree, file_path, original_declaration, doctype=None):
    """
    Write the ElementTree to a temp file (8.3-safe name in same directory),
    validate the temp file parses cleanly, then replace the original only if valid.
    Returns True on success, False on OS error, None on XML validation failure.
    """
    import shutil
    import tempfile

    dir_path = os.path.dirname(os.path.abspath(file_path))

    # Create temp file in same directory — empty prefix + 8 random chars + .bak = 8.3 compliant
    try:
        fd, tmp_path = tempfile.mkstemp(suffix='.bak', prefix='', dir=dir_path)
        os.close(fd)
        dbg(f"Temp file: {tmp_path}")
    except OSError as e:
        err(f"Could not create temp file in '{dir_path}': {e}")
        return False

    # --- Write to temp ---
    try:
        try:
            ET.indent(tree.getroot())
        except AttributeError:
            pass

        if original_declaration:
            tree.write(tmp_path, encoding='unicode', xml_declaration=True)
        else:
            tree.write(tmp_path, encoding='unicode', xml_declaration=False)

        # Re-inject DOCTYPE if present
        if doctype:
            with open(tmp_path, 'r', encoding='utf-8') as fh:
                content = fh.read()
            if original_declaration:
                first_newline = content.index('\n')
                content = content[:first_newline + 1] + doctype + '\n' + content[first_newline + 1:]
            else:
                content = doctype + '\n' + content
            with open(tmp_path, 'w', encoding='utf-8') as fh:
                fh.write(content)
            dbg(f"Re-injected DOCTYPE: {doctype}")

    except OSError as e:
        err(f"Could not write temp file '{tmp_path}': {e}")
        try: os.remove(tmp_path)
        except OSError: pass
        return False

    # --- Validate temp file ---
    try:
        ET.parse(tmp_path)
        dbg("Post-write XML validation passed.")
    except ET.ParseError as e:
        err(f"Written content failed XML validation: {e}")
        err("Original file was NOT modified.")
        try: os.remove(tmp_path)
        except OSError: pass
        return None  # signals exit 6

    # --- Replace original with validated temp ---
    try:
        shutil.copy2(tmp_path, file_path)
        dbg(f"Replaced '{file_path}' with validated temp file.")
    except OSError as e:
        err(f"Could not replace '{file_path}' with temp file: {e}")
        try: os.remove(tmp_path)
        except OSError: pass
        return False
    finally:
        try: os.remove(tmp_path)
        except OSError: pass

    return True


def main():
    global _debug

    parser = argparse.ArgumentParser(
        description='XML File Value Insert/Update/Delete utility',
        add_help=True
    )
    parser.add_argument('-f', '--file',       required=True,  help='Target XML file path')
    parser.add_argument('-p', '--path',       required=True,  help='XPath to target element')
    parser.add_argument('-a', '--attribute',  default=None,   help='Attribute name to get/set/delete')
    parser.add_argument('-v', '--value',      default=None,   help='Value to set')
    parser.add_argument('-c', '--create',     action='store_true', help='Create missing elements')
    parser.add_argument('-d', '--delete',     action='store_true', help='Delete element or attribute')
    parser.add_argument('-da', '--delete-all', action='store_true', dest='delete_all',
                        help='With -d, delete ALL elements matching the path (not just the first)')
    parser.add_argument('-so', '--search-only', action='store_true', dest='search_only',
                        help='Search only; no file changes')
    parser.add_argument('-cf', '--create-file', action='store_true', dest='create_file',
                        help='Create the XML file if it does not exist')
    parser.add_argument('--append', default=None, metavar='TAG',
                        help='Append a new child element with this tag under the element at -p')
    parser.add_argument('--set', nargs='+', default=[], metavar='KEY=VALUE',
                        help='Attribute assignments for --append (e.g. --set location=adx_spgm: suffix=jon.DAT)')
    parser.add_argument('--force', action='store_true',
                        help='With --append, always append even if identical element exists')
    parser.add_argument('--debug',            action='store_true', help='Verbose debug output')

    args = parser.parse_args()
    _debug = args.debug

    dbg(f"Sky runtime detected: {issky}")
    if issky:
        dbg(f"Mapping Sky path with os4690.mappath: {args.file}")
        args.file = mappath(args.file, False)
        dbg(f"Mapped file path: {args.file}")

    dbg(f"Args: file={args.file} path={args.path} attr={args.attribute} "
        f"value={args.value} create={args.create} create_file={args.create_file} "
        f"delete={args.delete} delete_all={args.delete_all} search_only={args.search_only} "
        f"append={args.append} set={args.set} force={args.force}")

    # Validate argument combinations
    if args.append and (args.delete or args.value is not None or args.attribute):
        err("--append cannot be combined with --delete, --value, or --attribute.")
        sys.exit(5)
    if args.set and not args.append:
        err("--set requires --append.")
        sys.exit(5)
    if args.attribute:
        import re
        if not re.match(r'^[A-Za-z_][\w\-\.]*$', args.attribute):
            err(f"Invalid XML attribute name: '{args.attribute}'  "
                f"(must start with a letter or underscore, no '=', spaces, or special characters)")
            sys.exit(5)
    # -da implies -d
    if args.delete_all:
        args.delete = True

    if args.delete and args.value is not None:
        err("Cannot use --value with --delete.")
        sys.exit(5)
    if args.delete and args.create:
        err("Cannot use --create with --delete.")
        sys.exit(5)
    if not args.delete and not args.search_only and not args.append and args.value is None:
        # No value, no delete, no search-only → treat as search-only
        dbg("No --value or --delete specified; defaulting to search-only mode.")
        args.search_only = True

    # Check file exists — create if requested
    if not os.path.exists(args.file):
        if args.create_file:
            # Derive root tag from first segment of path (strip predicates)
            import re
            first_seg = args.path.lstrip('./').split('/')[0]
            root_tag = re.sub(r'\[.*\]', '', first_seg) or 'root'
            dbg(f"File not found; creating new XML file with root <{root_tag}>: {args.file}")
            try:
                new_root = ET.Element(root_tag)
                new_tree = ET.ElementTree(new_root)
                ET.indent(new_root) if hasattr(ET, 'indent') else None
                new_tree.write(args.file, encoding='unicode', xml_declaration=True)
                print(f"Created file: {args.file}")
            except OSError as e:
                err(f"Could not create file '{args.file}': {e}")
                sys.exit(2)
        else:
            err(f"File not found: {args.file}  (use -cf to create)")
            sys.exit(1)

    # Parse XML
    try:
        dbg(f"Parsing XML file: {args.file}")
        # Detect XML declaration and DOCTYPE to preserve them
        with open(args.file, 'r', encoding='utf-8', errors='replace') as fh:
            first_line = fh.readline()
        has_declaration = first_line.strip().startswith('<?xml')
        doctype = detect_doctype(args.file)

        tree = ET.parse(args.file)
        root = tree.getroot()
        dbg(f"Root element: <{root.tag}>")
    except ET.ParseError as e:
        err(f"Could not parse XML file '{args.file}': {e}")
        sys.exit(3)
    except OSError as e:
        err(f"Could not read file '{args.file}': {e}")
        sys.exit(3)

    # Validate that the first path segment matches the document's root element tag
    import re as _re
    path_root = _re.sub(r'\[.*?\]', '', args.path.lstrip('./').split('/')[0])
    if path_root != root.tag:
        err(f"Path root '{path_root}' does not match document root <{root.tag}>. "
            f"Update your path to start with '{root.tag}/'.")
        sys.exit(5)
    dbg(f"Path root '{path_root}' matches document root <{root.tag}>")

    # --- Search only ---
    if args.search_only:
        el = root.find(strip_root_tag(root, args.path))
        if el is None:
            print(f"Not found: {args.path}")
            sys.exit(4)
        if args.attribute:
            val = el.get(args.attribute)
            if val is None:
                print(f"Attribute '{args.attribute}' not found on <{el.tag}>")
                sys.exit(4)
            print(f"Found: <{el.tag} {args.attribute}=\"{val}\">")
        else:
            print(f"Found: <{el.tag}> text={repr(el.text)}")
        sys.exit(0)

    # --- Delete ---
    if args.delete:
        del_path = strip_root_tag(root, args.path)
        deleted_count = 0
        if args.attribute:
            # Delete attribute from element
            el = root.find(del_path)
            if el is None:
                err(f"Element not found at path: {args.path}")
                sys.exit(4)
            if args.attribute not in el.attrib:
                err(f"Attribute '{args.attribute}' not found on <{el.tag}>")
                sys.exit(4)
            del el.attrib[args.attribute]
            dbg(f"Deleted attribute '{args.attribute}' from <{el.tag}>")
        else:
            # Delete element — need parent
            # Build parent path and child tag
            path_parts = del_path.rsplit('/', 1)
            if len(path_parts) == 1:
                parents = [root]
                child_tag = path_parts[0]
            else:
                parent_path, child_tag = path_parts
                if args.delete_all:
                    # findall to get ALL matching parents (e.g. every Controller/Extensions)
                    parents = root.findall(parent_path)
                else:
                    parents = [root.find(parent_path)]
                if not parents or parents[0] is None:
                    err(f"Parent element not found at: {parent_path}")
                    sys.exit(4)

            # Find and remove matching child element(s)
            if args.delete_all:
                deleted_count = 0
                for parent in parents:
                    targets = parent.findall(child_tag)
                    for target in targets:
                        parent.remove(target)
                        dbg(f"Deleted element <{target.tag}> from parent <{parent.tag}>")
                        deleted_count += 1
                if deleted_count == 0:
                    err(f"Element not found at path: {args.path}")
                    sys.exit(4)
            else:
                parent = parents[0]
                target = parent.find(child_tag)
                if target is None:
                    err(f"Element not found at path: {args.path}")
                    sys.exit(4)
                parent.remove(target)
                dbg(f"Deleted element <{target.tag}> from parent <{parent.tag}>")
                deleted_count = 1

        result = write_xml(tree, args.file, has_declaration, doctype)
        if result is False: sys.exit(2)
        if result is None: sys.exit(6)
        suffix = (f" @{args.attribute}" if args.attribute else "")
        count_str = f" ({deleted_count} elements)" if not args.attribute and args.delete_all else ""
        print(f"Deleted: {args.path}{suffix}{count_str}")
        sys.exit(0)

    # --- Append new child element ---
    if args.append:
        import re as _re2
        if _re2.search(r'[\[\]@\*]', args.append):
            err(f"--append tag must be a plain element name, got: '{args.append}'")
            sys.exit(5)

        # Parse --set key=value pairs
        new_attrs = {}
        for kv in args.set:
            if '=' not in kv:
                err(f"--set value must be in key=value format, got: '{kv}'")
                sys.exit(5)
            k, _, v = kv.partition('=')
            if not _re2.match(r'^[A-Za-z_][\w\-\.]*$', k):
                err(f"Invalid attribute name in --set: '{k}'")
                sys.exit(5)
            new_attrs[k] = v

        # Find parent element at -p
        parent_path = strip_root_tag(root, args.path)
        if parent_path == '.':
            parent = root
        else:
            parent = root.find(parent_path)
        if parent is None:
            err(f"Parent element not found: {args.path}")
            sys.exit(4)

        # Check for duplicate unless --force
        if not args.force:
            for existing in parent.findall(args.append):
                if existing.attrib == new_attrs and (existing.text or '').strip() == '':
                    print(f"Skipped: identical <{args.append}> already exists under <{parent.tag}>.")
                    print(f"  Use --force to append anyway.")
                    sys.exit(0)

        new_el = ET.SubElement(parent, args.append)
        for k, v in new_attrs.items():
            new_el.set(k, v)
        dbg(f"Appended <{args.append}> with attrs {new_attrs} under <{parent.tag}>")

        result = write_xml(tree, args.file, has_declaration, doctype)
        if result is False: sys.exit(2)
        if result is None: sys.exit(6)
        attrs_str = ' '.join(f'{k}="{v}"' for k, v in new_attrs.items())
        print(f"Appended: <{args.append} {attrs_str}/>  under <{parent.tag}>")
        sys.exit(0)

    # --- Set value ---
    el = find_or_create(root, args.path, args.create)
    if el is None:
        err(f"Element not found: {args.path}  (use -c to create)")
        sys.exit(4)

    if args.attribute:
        old_val = el.get(args.attribute)
        el.set(args.attribute, args.value)
        dbg(f"Set <{el.tag} {args.attribute}> = '{args.value}'  (was: {repr(old_val)})")
        print(f"Set attribute: <{el.tag} {args.attribute}=\"{args.value}\">")
    else:
        # Refuse to set text on an element that has child elements — would corrupt the XML
        if len(el) > 0:
            child_tags = ', '.join(f'<{c.tag}>' for c in el)
            err(f"Cannot set text on <{el.tag}> — it contains child elements ({child_tags}). "
                f"Use --append to add a child, or -a to set an attribute.")
            sys.exit(5)
        old_text = el.text
        el.text = args.value
        dbg(f"Set <{el.tag}> text = '{args.value}'  (was: {repr(old_text)})")
        print(f"Set text: <{el.tag}> = '{args.value}'")

    result = write_xml(tree, args.file, has_declaration, doctype)
    if result is False: sys.exit(2)
    if result is None: sys.exit(6)

    sys.exit(0)


if __name__ == '__main__':
    main()
