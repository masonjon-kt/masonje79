# fvinxml.py — XML File Value Insert/Update/Delete Utility

A command-line utility and importable Python library for editing XML files using the ElementTree object model. No manual string parsing — all operations work through the XML document tree.

## Requirements

- Python 3.6+
- No third-party packages required (uses stdlib `xml.etree.ElementTree`)

---

## Features

- Set element text or attribute values
- Append new child elements with multiple attributes in one command
- Delete elements or attributes (single or all matches)
- Cross-parent delete-all (remove matching elements across multiple parent nodes)
- Auto-create missing path elements with `-c`
- Create new XML file from scratch with `-cf`
- Duplicate detection on append (skips if identical element exists)
- Preserves `<?xml ...?>` declaration and `<!DOCTYPE ...>` on every write
- Write-protect: changes are written to a temp file first, validated, then replace the original
- Short filename (8.3) compatible temp files

---

## Path Format

All paths **must include the root element** as the first segment:

```
RootElement/Child/Grandchild
RootElement/Child[@attr='value']/Grandchild
RootElement/Child[1]/Grandchild
```

The root element in the path is validated against the document root. If they don't match, the command fails with a clear error.

---

## Command-Line Usage

```
python3 fvinxml.py -f <file> -p <xpath> [options]
```

### Options

| Flag | Description |
|------|-------------|
| `-f`, `--file` | Target XML file path (required) |
| `-p`, `--path` | XPath to the target element (required) |
| `-a`, `--attribute` | Attribute name to get/set/delete |
| `-v`, `--value` | Value to set on element text or attribute |
| `-c`, `--create` | Create missing path elements if they don't exist |
| `-d`, `--delete` | Delete the matched element (or attribute if `-a` given) |
| `-da`, `--delete-all` | Delete ALL elements matching the path (implies `-d`) |
| `--append TAG` | Append a new child element with the given tag under `-p` |
| `--set KEY=VALUE` | Attribute(s) for the appended element (repeatable) |
| `--force` | With `--append`, always append even if identical element exists |
| `-so`, `--search-only` | Search only; no file changes |
| `-cf`, `--create-file` | Create the XML file if it does not exist |
| `--debug` | Verbose debug output |

### Exit Codes

| Code | Meaning |
|------|---------|
| 0 | Success / element found |
| 1 | Target file not found |
| 2 | File could not be created or written |
| 3 | File could not be read or parsed |
| 4 | Element or attribute not found |
| 5 | Invalid arguments |
| 6 | Written content failed XML validation; original file unchanged |

---

## Examples

### Search / Check Existence

```bash
# Check if a Controller element exists (exit 0 = found, 4 = not found)
python3 fvinxml.py -f contrext.xml -p "ControllerExtensions/Controller[@id='MM']"

# Check if a specific Extension exists by attribute value
python3 fvinxml.py -f contrext.xml -p "ControllerExtensions/Controller[@id='FC']/Extensions/Extension[@suffix='ADXXTSJ8.DAT']"

# Check if any Extension exists under a Controller (finds first match)
python3 fvinxml.py -f contrext.xml -p "ControllerExtensions/Controller[@id='FC']/Extensions/Extension"

# Find an element and display a specific attribute's value
python3 fvinxml.py -f contrext.xml \
  -p "ControllerExtensions/Controller[@id='FC']/Extensions/Extension[@suffix='ADXXTSJ8.DAT']" \
  -a location

# Check an attribute on a simple element
python3 fvinxml.py -f contrext.xml -p "ControllerExtensions/FileVersion" -a version
```

### Set Values

```bash
# Set an attribute on an existing element
python3 fvinxml.py -f contrext.xml -p "ControllerExtensions/FileVersion" -a version -v "v6r3"

# Set element text (only valid for elements with no child elements)
python3 fvinxml.py -f contrext.xml -p "ControllerExtensions/SomeTextElement" -v "hello"

# Set an attribute, creating the element path if it doesn't exist
python3 fvinxml.py -f contrext.xml -p "ControllerExtensions/NewSection/Item" -a name -v "test" -c
```

### Append Child Elements

```bash
# Append a new Controller element with an id attribute
python3 fvinxml.py -f contrext.xml -p "ControllerExtensions" --append Controller --set id="MM"

# Append an Extensions container under a specific Controller
python3 fvinxml.py -f contrext.xml -p "ControllerExtensions/Controller[@id='MM']" --append Extensions

# Append Extension entries under a Controller (duplicate check on by default)
python3 fvinxml.py -f contrext.xml \
  -p "ControllerExtensions/Controller[@id='MM']/Extensions" \
  --append Extension --set location="adx_spgm:" suffix="ADXXTSJ8.DAT"

python3 fvinxml.py -f contrext.xml \
  -p "ControllerExtensions/Controller[@id='MM']/Extensions" \
  --append Extension --set location="adx_spgm:" suffix="ADXXTSSH.DAT"

# Force append even if identical element already exists
python3 fvinxml.py -f contrext.xml \
  -p "ControllerExtensions/Controller[@id='MM']/Extensions" \
  --append Extension --set location="adx_spgm:" suffix="ADXXTSJ8.DAT" --force
```

### Delete

```bash
# Delete a specific Extension entry (first match only)
python3 fvinxml.py -f contrext.xml \
  -p "ControllerExtensions/Controller[@id='MM']/Extensions/Extension[@suffix='ADXXTSDK.DAT']" -d

# Delete ALL duplicate entries with the same suffix under one Controller
python3 fvinxml.py -f contrext.xml \
  -p "ControllerExtensions/Controller[@id='MM']/Extensions/Extension[@suffix='ADXXTpoo.DAT']" -da

# Delete ALL matching entries across ALL Controllers (cross-parent)
python3 fvinxml.py -f contrext.xml \
  -p "ControllerExtensions/Controller/Extensions/Extension[@suffix='ADXXTSSH.DAT']" -da

# Delete an entire Controller block
python3 fvinxml.py -f contrext.xml -p "ControllerExtensions/Controller[@id='MM']" -d

# Delete a single attribute from a matched element
python3 fvinxml.py -f contrext.xml \
  -p "ControllerExtensions/Controller[@id='MM']/Extensions/Extension[@suffix='ADXXTSDK.DAT']" \
  -a location -d
```

### Create New File

```bash
# Create a new XML file and build structure in one pass
python3 fvinxml.py -f new.xml -p "ControllerExtensions" -cf
python3 fvinxml.py -f new.xml -p "ControllerExtensions" --append Controller --set id="FC"
python3 fvinxml.py -f new.xml \
  -p "ControllerExtensions/Controller[@id='FC']" --append Extensions
python3 fvinxml.py -f new.xml \
  -p "ControllerExtensions/Controller[@id='FC']/Extensions" \
  --append Extension --set location="adx_spgm:" suffix="ADXXTSJ8.DAT"
```

---

## Library Usage

Import `fvinxml` and use the low-level helper functions directly. All file I/O goes through `write_xml` which handles temp file, validation, and atomic replace.

```python
import xml.etree.ElementTree as ET
from fvinxml import (
    find_or_create,
    strip_root_tag,
    detect_doctype,
    write_xml,
)

# --- Load file ---
file_path = 'contrext.xml'
tree = ET.parse(file_path)
root = tree.getroot()

with open(file_path, 'r') as fh:
    has_declaration = fh.readline().strip().startswith('<?xml')
doctype = detect_doctype(file_path)

# --- Search ---
el = root.find(strip_root_tag(root, "ControllerExtensions/Controller[@id='FC']"))
if el is not None:
    print(f"Found: {el.tag} {el.attrib}")

# --- Set attribute ---
el = find_or_create(root, "ControllerExtensions/FileVersion", create=False)
if el is not None:
    el.set('version', 'v6r3')
    write_xml(tree, file_path, has_declaration, doctype)

# --- Append child element ---
parent = root.find(strip_root_tag(root, "ControllerExtensions/Controller[@id='FC']/Extensions"))
if parent is not None:
    new_el = ET.SubElement(parent, 'Extension')
    new_el.set('location', 'adx_spgm:')
    new_el.set('suffix', 'NEWFILE.DAT')
    write_xml(tree, file_path, has_declaration, doctype)

# --- Delete element ---
parent = root.find(strip_root_tag(root, "ControllerExtensions/Controller[@id='FC']/Extensions"))
if parent is not None:
    target = parent.find("Extension[@suffix='NEWFILE.DAT']")
    if target is not None:
        parent.remove(target)
        write_xml(tree, file_path, has_declaration, doctype)

# --- Delete all matching across all parents ---
for parent in root.findall("Controller/Extensions"):
    for target in parent.findall("Extension[@suffix='ADXXTSSH.DAT']"):
        parent.remove(target)
write_xml(tree, file_path, has_declaration, doctype)
```

### `write_xml` Return Values

| Return | Meaning |
|--------|---------|
| `True` | Success — file updated |
| `False` | OS error writing temp file or replacing original |
| `None` | Written content failed XML parse validation; original unchanged |

---

## Known Limitations

| Feature | Status |
|---------|--------|
| `<!DOCTYPE ...>` | Preserved on write |
| XML comments `<!-- -->` | **Stripped** by ElementTree on write |
| Processing instructions `<?...?>` | **Stripped** by ElementTree on write |
| CDATA sections | **Converted** to plain text |
| XML namespaces | Supported but path must use `{uri}tag` notation |
| XPath axes (`//`) | **Not supported** (ElementTree subset only) |
| XPath functions (`contains()`, `text()`) | **Not supported** |
| Original whitespace/formatting | Reformatted by `ET.indent()` on every write |
