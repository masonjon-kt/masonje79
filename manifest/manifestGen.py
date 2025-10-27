import os
import hashlib

script_dir = os.path.dirname(os.path.abspath(__file__))
# Configuration
manifest_file = f'{script_dir}/manifestGen.txt'
manifest_output = f'{script_dir}/manifest.txt'

base_url = 'http://kremrepo.kroger.com/isilon/POS/'  # Change to your actual base URL

def sha1_of_file(filepath):
    sha1 = hashlib.sha1()
    with open(filepath, 'rb') as f:
        for chunk in iter(lambda: f.read(8192), b''):
            sha1.update(chunk)
    return sha1.hexdigest()

def main():
    script_dir = os.path.dirname(os.path.abspath(__file__))
    manifest_path = os.path.join(script_dir, manifest_file)

    if not os.path.isfile(manifest_path):
        print(f"Manifest file '{manifest_file}' not found.")
        return

    with open(manifest_path, 'r') as f:
        filenames = [line.strip() for line in f if line.strip()]

    for filename in filenames:
        file_path = os.path.join(script_dir, filename)
        if os.path.isfile(file_path):
            # Check if file already exists in manifest_output and size matches
            skip = False
            size = os.path.getsize(file_path)
            if os.path.isfile(manifest_output):
                with open(manifest_output, 'r') as mf:
                    for line in mf:
                        parts = line.strip().split()
                        if len(parts) >= 4 and parts[0] == f"name={filename}":
                            size_part = [p for p in parts if p.startswith('size=')]
                            if size_part and int(size_part[0].split('=')[1]) == size:
                                skip = True
                                break
            if skip:
                print(f"Skipping '{filename}': already in manifest with matching size.")
                continue
            
            sha1 = sha1_of_file(file_path)
            url = base_url + filename
            line = f"name={filename} sha1={sha1} size={size} url={url}"

            with open(manifest_output, 'a') as mf:
                mf.write(line + '\n')
                print(f"Added to manifest: {line}")

        else:
            print(f"File '{filename}' not found in directory.")

if __name__ == '__main__':
    main()
