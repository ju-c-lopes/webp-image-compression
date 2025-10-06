#!/bin/bash

compression_level=80

if [ ! -z "$1" ]; then
    compression_level=$1
fi

apt-get update
apt-get install -y zip libjpeg-dev libpng-dev libtiff-dev libgif-dev
CWEBP="$PWD/task-dep/bin/cwebp"
DWEBP="$PWD/task-dep/bin/dwebp"

DIR=$PWD
INPUT_DIR="$PWD/images"
OUTPUT_DIR="$PWD/optimized"

mkdir -p $OUTPUT_DIR
cd images

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

sleep 5
cd ..
zip -r "$DIR/optimized.zip" $OUTPUT_DIR

echo "Total size non-optimized: $((total / 1024)) KB."
echo "Total size optimized: $((optimized / 1024)) KB.\n"

