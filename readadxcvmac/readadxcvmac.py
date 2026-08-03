def scan_keyed_file(filepath):
    RECORD_SIZE = 128
    KEY_SIZE = 3

    with open(filepath, "rb") as f:
        data = f.read()

    results = []

    for i in range(len(data) - RECORD_SIZE):
        key = data[i:i+KEY_SIZE]

        # check if key looks like ASCII numeric (001–999)
        if all(48 <= b <= 57 for b in key):
            record = data[i:i+RECORD_SIZE]

            term = key.decode("ascii")

            results.append((term, record))

    return results


def print_results(records):
    all_results = []

    for term, rec in records:
        # MAC is stored at fixed offset 4 for 6 bytes.
        mac_at_offset_4 = rec[4:10].hex().upper()

        all_results.append(
            {
                "terminal": term,
                "record_hex": rec.hex().upper(),
                "mac_address": mac_at_offset_4,
            }
        )

    return all_results


if __name__ == "__main__":
    path = "/home/jm43349/github/masonje79/readadxcvmac/adxcvmac.dat"
    records = scan_keyed_file(path)
    results = print_results(records)
    print(f"Returned {len(results)} records")
    for x in results:
        print(f"Terminal: {x['terminal']}, MAC Address: {x['mac_address']}")
