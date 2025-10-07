#!/bin/bash

compression_level=80

if [ ! -z "$1" ]; then
    compression_level=$1
fi

chmod 777 "$PWD/task-dep/original-hashes.json"

echo "🔒 Generating integrity hashes..."
python3 <<'EOF'
import os, hashlib, json

image_dir = f"{os.getcwd()}/images"
output_dir = f"{os.getcwd()}/task-dep"
output_file = os.path.join(output_dir, "original_hashes.json")

print(f"{image_dir}\n{output_dir}\n{output_file}")
os.system(f"ls -la {output_dir}")

hashes = {}

for filename in os.listdir(image_dir):
    path = os.path.join(image_dir, filename)
    print(f"Hashing {path}...")
    if os.path.isfile(path):
        h = hashlib.sha256()
        with open(path, "rb") as f:
            for chunk in iter(lambda: f.read(8192), b""):
                h.update(chunk)
        hashes[filename] = h.hexdigest()

with open(output_file, "w") as f:
    json.dump(hashes, f, indent=2)
    f.flush()

print(f"✅ Saved hashes to {output_file}")
EOF

sleep 20

apt-get update
apt-get install -y zip libjpeg-dev libpng-dev libtiff-dev libgif-dev
CWEBP="$PWD/task-dep/bin/cwebp"
DWEBP="$PWD/task-dep/bin/dwebp"

DIR=$PWD
INPUT_DIR="$PWD/images"
OUTPUT_DIR="$PWD/optimized"

mkdir -p $OUTPUT_DIR
cd images

shopt -s nocaseglob
for img in *.jpg *.jpeg *.png; do
    [ -e "$img" ] || continue
    filename=$(basename "$img")
    output="$OUTPUT_DIR/${filename%.*}.webp"

    original_size=$(stat -c%s $img)
    $CWEBP -q $compression_level $img -o $output
    optimized_size=$(stat -c%s $output)

    ((total+=original_size))
    ((optimized+=optimized_size))
done
shopt -u nocaseglob

sleep 5
cd ..
zip -r "$DIR/optimized.zip" $OUTPUT_DIR

echo "Total size non-optimized: $((total / 1024)) KB."
echo "Total size optimized: $((optimized / 1024)) KB.\n"

