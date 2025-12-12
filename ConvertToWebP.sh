#!/bin/bash

echo "=== WebP Conversion Started: $(date) ==="
echo "Number of files: $#"
echo "Files: $@"
echo ""

# Find cwebp (check common locations)
if command -v cwebp &> /dev/null; then
    CWEBP_PATH=$(which cwebp)
    echo "Found cwebp at: $CWEBP_PATH"
elif [ -f "/opt/homebrew/bin/cwebp" ]; then
    CWEBP_PATH="/opt/homebrew/bin/cwebp"
    echo "Found cwebp at: $CWEBP_PATH"
elif [ -f "/usr/local/bin/cwebp" ]; then
    CWEBP_PATH="/usr/local/bin/cwebp"
    echo "Found cwebp at: $CWEBP_PATH"
else
    echo "ERROR: cwebp not found!"
    osascript -e 'display notification "cwebp not found. Install with: brew install webp" with title "WebP Error"'
    exit 1
fi

# Process each file
for INPUT_FILE in "$@"; do
    echo "----------------------------------------"
    echo "Processing: $INPUT_FILE"
    
    # Skip if file doesn't exist
    if [ ! -f "$INPUT_FILE" ]; then
        echo "ERROR: File not found - $INPUT_FILE"
        continue
    fi
    
    # Get file extension and basename
    EXTENSION="${INPUT_FILE##*.}"
    BASENAME="${INPUT_FILE%.*}"
    
    # Convert extension to lowercase (bash 3.2 compatible)
    EXTENSION_LOWER=$(echo "$EXTENSION" | tr '[:upper:]' '[:lower:]')
    
    echo "Extension: $EXTENSION_LOWER"
    echo "Basename: $BASENAME"
    
    # Get original image width using sips (built-in macOS tool) - BEFORE conversion
    ORIGINAL_WIDTH=$(sips -g pixelWidth "$INPUT_FILE" 2>&1 | grep "pixelWidth:" | awk '{print $2}')

    echo "Original width: ${ORIGINAL_WIDTH}px"

    if [ -z "$ORIGINAL_WIDTH" ] || [ "$ORIGINAL_WIDTH" == "0" ]; then
        echo "ERROR: Could not determine width of $INPUT_FILE"
        continue
    fi

    # Determine the WebP source file
    if [[ "$EXTENSION_LOWER" == "webp" ]]; then
        WEBP_FILE="$INPUT_FILE"
        echo "File is already WebP"
    else
        # Convert to WebP first
        WEBP_FILE="${BASENAME}.webp"
        echo "Converting to WebP: $WEBP_FILE"

        "$CWEBP_PATH" -q 90 "$INPUT_FILE" -o "$WEBP_FILE"

        if [ $? -ne 0 ]; then
            echo "ERROR: Failed to convert $INPUT_FILE"
            continue
        fi
        echo "Conversion successful"
    fi

    # Define target widths
    WIDTHS=(400 800 1200)
    
    # Create responsive versions
    for WIDTH in "${WIDTHS[@]}"; do
        if [ "$WIDTH" -lt "$ORIGINAL_WIDTH" ]; then
            OUTPUT_FILE="${BASENAME}-${WIDTH}w.webp"
            echo "Creating ${WIDTH}w version: $OUTPUT_FILE"
            "$CWEBP_PATH" -q 85 -resize "$WIDTH" 0 "$WEBP_FILE" -o "$OUTPUT_FILE"
            
            if [ $? -eq 0 ]; then
                echo "  ✓ Created successfully"
            else
                echo "  ✗ Failed to create"
            fi
        else
            echo "Skipping ${WIDTH}w (original is only ${ORIGINAL_WIDTH}px)"
        fi
    done
    
    echo "✓ Completed: $(basename "$WEBP_FILE")"
    echo ""
done

echo "=== Conversion Complete: $(date) ==="

osascript -e 'display notification "All images converted successfully" with title "WebP Conversion Complete"'