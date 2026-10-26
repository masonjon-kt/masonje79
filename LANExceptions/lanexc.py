import os
from collections import Counter

try:
    from os4690 import mappath
    issky = True
except ImportError:
    issky = False

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))

RECORD_SIZE = 80
PATH_OFFSET = 2
PATH_SIZE = 54

FILES = [
    "c:\\adx_sdt1\\ADXLNDMF.DAT",
    "c:\\adx_sdt1\\ADXLNDSF.DAT",
]


def read_records(filepath):
    with open(filepath, "rb") as f:
        data = f.read()

    records = []
    for i in range(0, len(data), RECORD_SIZE):
        records.append(data[i:i + RECORD_SIZE])

    return records


def decode_record(rec):
    flag = rec[0:PATH_OFFSET].hex().upper()

    path_bytes = rec[PATH_OFFSET:PATH_OFFSET + PATH_SIZE]
    nul = path_bytes.find(b"\x00")
    if nul != -1:
        path_bytes = path_bytes[:nul]
    path = path_bytes.decode("ascii", errors="replace")

    tail = rec[PATH_OFFSET + PATH_SIZE:]

    return {
        "flag": flag,
        "path": path,
        "tail_hex": tail.hex().upper(),
    }


def report(filepath):
    if issky:
        resolved = mappath(filepath, False)
    else:
        basename = filepath.replace("\\", "/").rsplit("/", 1)[-1]
        resolved = os.path.join(SCRIPT_DIR, basename)

    print(f"=== {filepath} ===")
    records = read_records(resolved)
    count = 0
    flag_counter = Counter()
    prefix_counter = Counter()
    for line_num, rec in enumerate(records, start=1):
        fields = decode_record(rec)
        if fields["flag"] == "0000":
            continue
        count += 1
        #print(f"Line {line_num}: flag={fields['flag']} path={fields['path']} tail={fields['tail_hex']}")

        flag_counter[fields["flag"]] += 1
        path = fields["path"]
        prefix = path.split(":", 1)[0] if ":" in path else "(none)"
        prefix_counter[prefix] += 1

    summary = []
    for k, v in flag_counter.most_common():
        summary.append(f"f:{k}:{v}")
    for k, v in prefix_counter.most_common():
        summary.append(f"p:{k}:{v}")
    summary.append(f"t:{count}")

    for entry in summary:
        print(entry)
    print()


if __name__ == "__main__":
    for filepath in FILES:
        report(filepath)
