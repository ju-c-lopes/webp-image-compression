#!/bin/bash
set -euo pipefail

compression_level=${COMPRESSION_LEVEL:-80}
if [ -n "${1:-}" ]; then
    compression_level=$1
fi

MAX_SIZE_KB=${MAX_SIZE_KB:-100}
MIN_QUALITY=${MIN_QUALITY:-50}
QUALITY_STEP=${QUALITY_STEP:-5}
RESORT_TO_SIZE=${RESORT_TO_SIZE:-true}
CWEBP_EXTRA_FLAGS=${CWEBP_EXTRA_FLAGS:-"-m 6 -pass 10 -af -sns 50 -f 70"}

TARGET_BYTES=$((MAX_SIZE_KB * 1024))
declare -a CWEBP_EXTRA_ARGS=()
if [ -n "${CWEBP_EXTRA_FLAGS// /}" ]; then
    # shellcheck disable=SC2206
    CWEBP_EXTRA_ARGS=($CWEBP_EXTRA_FLAGS)
fi

total=0
optimized=0
declare -a oversized_images=()

echo "🎯 Target max size: ${MAX_SIZE_KB} KB | floor quality: ${MIN_QUALITY}"

if [ -e "$PWD/task-dep/original-hashes.json" ]; then
    chmod 777 "$PWD/task-dep/original-hashes.json"
fi

echo "🔒 Generating integrity hashes..."
python3 <<'EOF'
import os, hashlib, json

image_backup_dir = f"{os.getcwd()}/images-backup"
image_dir = f"{os.getcwd()}/images"
os.system(f"cp -r {image_backup_dir}/* {image_dir}/")
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

if command -v apt-get >/dev/null 2>&1; then
    if [ "$EUID" -eq 0 ]; then
        apt-get update
        apt-get install -y zip libjpeg-dev libpng-dev libtiff-dev libgif-dev
    else
        echo "⚠️ Skipping apt-get install (run with sudo if you need those packages)."
    fi
fi
CWEBP="$PWD/task-dep/bin/cwebp"
DWEBP="$PWD/task-dep/bin/dwebp"

DIR=$PWD
INPUT_DIR="$PWD/images"
OUTPUT_DIR="$PWD/optimized"

mkdir -p "$OUTPUT_DIR"
cd images

shopt -s nocaseglob
for img in *.jpg *.jpeg *.png; do
    [ -e "$img" ] || continue
    filename=$(basename "$img")
    output="$OUTPUT_DIR/${filename%.*}.webp"
    
    original_size=$(stat -c%s "$img")
    ((total+=original_size))
    
    quality=$compression_level
    optimized_size=0
    
    encode_with_quality() {
        rm -f "$output"
        "$CWEBP" -q "$1" "${CWEBP_EXTRA_ARGS[@]}" "$img" -o "$output"
    }
    
    encode_with_quality "$quality"
    optimized_size=$(stat -c%s "$output")
    
    while (( optimized_size > TARGET_BYTES )) && (( quality > MIN_QUALITY )); do
        quality=$((quality - QUALITY_STEP))
        if (( quality < MIN_QUALITY )); then
            quality=$MIN_QUALITY
        fi
        encode_with_quality "$quality"
        optimized_size=$(stat -c%s "$output")
        if (( quality == MIN_QUALITY )); then
            break
        fi
    done
    
    if (( optimized_size > TARGET_BYTES )) && [[ "${RESORT_TO_SIZE,,}" == "true" ]]; then
        rm -f "$output"
        "$CWEBP" -size "$TARGET_BYTES" "${CWEBP_EXTRA_ARGS[@]}" "$img" -o "$output" || true
        optimized_size=$(stat -c%s "$output" 2>/dev/null || echo 0)
    fi
    
    if (( optimized_size == 0 )); then
        echo "⚠️ Failed to create optimized file for $filename"
        oversized_images+=("$filename (conversion failed)")
        continue
    fi
    
    if (( optimized_size > TARGET_BYTES )); then
        echo "⚠️ $filename still above ${MAX_SIZE_KB} KB (actual: $((optimized_size / 1024)) KB)"
        oversized_images+=("$filename ($((optimized_size / 1024)) KB)")
    else
        echo "✅ $filename optimized to $((optimized_size / 1024)) KB at quality ${quality}"
    fi
    
    ((optimized+=optimized_size))
done
shopt -u nocaseglob

sleep 5
cd ..
zip -r "$DIR/optimized.zip" "$OUTPUT_DIR"

echo "Total size non-optimized: $((total / 1024)) KB."
echo "Total size optimized: $((optimized / 1024)) KB.\n"

