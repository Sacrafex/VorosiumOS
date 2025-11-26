# Resolve paths relative to the script's location
SCRIPT_DIR="$(cd -- "$(dirname -- "$0")" && pwd)"
INIT_FILE="$SCRIPT_DIR/init"

# check init
if [ ! -f "$INIT_FILE" ]; then
  echo "Error: /init file is missing in the ramdisk root."
  exit 1
fi

# verify path
INIT_ABS_PATH=$(readlink -f "$INIT_FILE")
echo "Using /init file at: $INIT_ABS_PATH"

chmod +x "$INIT_FILE"

# Check for required commands
for cmd in cpio gzip; do
  if ! command -v $cmd &> /dev/null; then
    echo "Error: Required command '$cmd' is not installed."
    exit 1
  fi
done

# Use absolute path for output directory
OUTPUT_DIR="$SCRIPT_DIR/../"

# check output
if [ ! -w "$OUTPUT_DIR" ]; then
  echo "Error: Output directory '$OUTPUT_DIR' is not writable."
  exit 1
fi

# Automatically change to the script directory
cd "$SCRIPT_DIR" || { echo "Error: Failed to change to script directory."; exit 1; }

# build disk
echo "Building ramdisk..."
# Exclude ramdisk.img from being included in the ramdisk
# Ensure find starts from the script directory
if ! find "$SCRIPT_DIR" \( -name "ramdisk.img" -prune \) -o -print | cpio -H newc -o | gzip > "${OUTPUT_DIR}ramdisk.img"; then
  echo "Error: Failed to create ramdisk."
  exit 1
fi

echo "Ramdisk built successfully at ${OUTPUT_DIR}ramdisk.img"
