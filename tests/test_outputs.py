import os, hashlib, subprocess, tempfile, json


IMAGE_DIR = os.path.join(os.getcwd(), "images")
OPTIMIZED_DIR = os.path.join(os.getcwd(), "optimized")
HASH_FILE = os.path.join(os.getcwd(), "task-dep/original_hashes.json")


def sha256(path: str) -> str:
    """Calculate the SHA256 hash of a file."""
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(8192), b""):
            h.update(chunk)
    return h.hexdigest()


def has_webp_magic(path: str) -> bool:
    """Check if a file has the webp magic number."""
    with open(path, "rb") as f:
        header = f.read(12)
    return header.startswith(b"RIFF") and header[8:12] == b"WEBP"


def can_decode_converted_image(path: str) -> bool:
    """Check if a webp image can be decoded back to its original format."""
    try:
        proc = subprocess.run([os.path.join(os.getcwd(), "task-dep/bin/cwebp"), path, "-o", os.devnull], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        return proc.returncode == 0
    except FileNotFoundError:
        return False


def decode_and_measure(path: str) -> int:
    """Decode a webp image into a temporary file and return its size."""
    with tempfile.NamedTemporaryFile(delete=False) as temp_file:
        temp_path = temp_file.name
    try:
        proc = subprocess.run([os.path.join(os.getcwd(), "task-dep/bin/dwebp"), path, "-o", temp_file.name], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        if proc.returncode != 0:
            return 0
        return os.stat(temp_path).st_size
    finally:
        try: os.remove(temp_path)
        except OSError: pass


def check_temp_cwebp_conversion_images(original_image_path) -> bool:
    """Check if the cwebp tool can convert images."""
    with tempfile.NamedTemporaryFile(delete=False) as temp_file:
        temp_path = temp_file.name
    try:
        os.system(f"{os.path.join(os.getcwd(), 'task-dep/bin/cwebp')} -q 80 {original_image_path} -o {temp_path}")
        return can_decode_converted_image(temp_path)
    except FileNotFoundError:
        return False


def test_optimized_images():
    """
    Check if non_optimized_images exists, verifying that list is not empty.
    Check if cwebp tool can convert an image.
    Check if images were really converted.
    Check if optimized images have webp magic number.
    Check if optimized images can be decoded back to original format.
    Check if optimized images are smaller than original images.
    Check if decoded images are reasonable, over 30% of original size.
    Check if original images were not modified by comparing their hashes.
    """
    non_optimized_images = [f for f in os.listdir(IMAGE_DIR) if f.lower().endswith((".jpg", ".jpeg", ".png"))]
    assert non_optimized_images, "No source images found for testing"

    for image in non_optimized_images:
        base = os.path.splitext(image)[0]
        original_image_path = os.path.join(IMAGE_DIR, image)
        optimized_image_path = os.path.join(OPTIMIZED_DIR, f"{base}.webp")

        # 1) Check if cwebp tool can convert the image
        assert check_temp_cwebp_conversion_images(original_image_path), f"cwebp tool failed to convert {original_image_path}"

        # 2) Check if optimized image exists
        assert os.path.exists(optimized_image_path), f"Missing optimized image {optimized_image_path}"

        # 3) Validate webp magic number in optimized image
        assert has_webp_magic(optimized_image_path), f"{optimized_image_path} missing webp magic number"
        assert can_decode_converted_image(optimized_image_path), f"Cannot decode optimized image {optimized_image_path}"

        # 4) Get image sizes
        original_size = os.stat(original_image_path).st_size
        optimized_size = os.stat(optimized_image_path).st_size
        decoded_size = decode_and_measure(optimized_image_path)

        # 5) Check size reduction
        assert optimized_size < original_size, f"Optimized image {optimized_image_path} is not smaller than original"

        # 6) Check decoded size is reasonable, over 30% of original
        min_reasonable_size = max(1000, int(original_size * 0.3))
        assert decoded_size > min_reasonable_size, f"Decoded size of {optimized_image_path} is unreasonably small"

        # 7) Check that original image is unchanged
        with open(HASH_FILE,"r") as fh:
            expected = json.load(fh)
        image_path = original_image_path.split("/")[-1]
        assert sha256(original_image_path) == expected[image_path], f"Original image {original_image_path} has been modified"
