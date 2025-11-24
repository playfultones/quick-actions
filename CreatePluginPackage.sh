#!/bin/bash

# Create a temporary script file with the full signing logic
SCRIPT_FILE="/tmp/sign_notarize_plugin_$$.sh"

cat > "$SCRIPT_FILE" << 'SCRIPT_CONTENT'
#!/bin/zsh

# Color output functions (define these FIRST before any errors can occur)
red_echo() {
    echo -e "\033[0;31m$1\033[0m"
}

green_echo() {
    echo -e "\033[0;32m$1\033[0m"
}

yellow_echo() {
    echo -e "\033[0;33m$1\033[0m"
}

blue_echo() {
    echo -e "\033[0;34m$1\033[0m"
}

# Start with less strict error handling for sourcing
set -o pipefail
if [[ "${TRACE-0}" == "1" ]]; then
    set -o xtrace
fi

# Try to source user's .zshrc to get environment variables
if [ -f ~/.zshrc ]; then
    blue_echo "→ Sourcing ~/.zshrc for environment variables..."
    source ~/.zshrc 2>/dev/null || yellow_echo "Warning: Could not source ~/.zshrc completely"
else
    yellow_echo "Warning: ~/.zshrc not found"
fi

# Now enable strict error handling for the rest
set -o errexit
set -o nounset

# Execute command with description
exec_cmd() {
    local description="$1"
    local command="$2"
    blue_echo "→ ${description}"
    eval "${command}"
    local cmd_status=$?
    if [ $cmd_status -ne 0 ]; then
        red_echo "✗ Command failed with status ${cmd_status}"
        red_echo "✗ Stopping execution due to error"
        exit $cmd_status
    fi
    return 0
}

# Function to check if bundle is already signed
is_bundle_signed() {
    local bundle_path="$1"
    if codesign --verify --deep --strict "$bundle_path" 2>/dev/null; then
        return 0
    else
        return 1
    fi
}

# Function to check if bundle is already notarized
is_bundle_notarized() {
    local bundle_path="$1"
    if stapler validate "$bundle_path" 2>/dev/null | grep -q "The validate action worked"; then
        return 0
    else
        return 1
    fi
}

# Function to sign and notarize a plugin bundle
sign_and_notarize_bundle() {
    local bundle_path="$1"
    local format_name="$2"
    local lower_format_name="$(echo "${format_name}" | tr '[:upper:]' '[:lower:]')"
    local zip_name="/tmp/${lower_format_name}_bundle_$(date +%s).zip"

    if [ ! -d "${bundle_path}" ]; then
        yellow_echo "${format_name} bundle not found at: ${bundle_path}"
        return 1
    fi

    # Check if already signed and notarized
    blue_echo "→ Checking if ${format_name} bundle is already signed and notarized..."
    local already_signed=false
    local already_notarized=false

    if is_bundle_signed "$bundle_path"; then
        green_echo "✓ Bundle is already code signed"
        already_signed=true
    else
        yellow_echo "⚠ Bundle is not signed"
    fi

    if is_bundle_notarized "$bundle_path"; then
        green_echo "✓ Bundle is already notarized and stapled"
        already_notarized=true
    else
        yellow_echo "⚠ Bundle is not notarized"
    fi

    # If already signed and notarized, skip the process
    if [ "$already_signed" = true ] && [ "$already_notarized" = true ]; then
        green_echo "🎉 ${format_name} bundle is already signed and notarized. Skipping..."
        return 0
    fi

    # Proceed with signing and notarization
    echo "Signing and notarizing ${format_name} bundle with path: ${bundle_path}..."

    # Sign any dylibs in Contents/Frameworks first (inside-out signing)
    local frameworks_dir="${bundle_path}/Contents/Frameworks"
    if [ -d "${frameworks_dir}" ]; then
        blue_echo "→ Found Frameworks directory, signing dylibs first..."
        for dylib in "${frameworks_dir}"/*.dylib; do
            if [ -f "$dylib" ]; then
                exec_cmd "Signing $(basename "$dylib")..." \
                         "codesign --force --verify --verbose --options runtime --sign \"${AppleCertName}\" \"${dylib}\""
                green_echo "✓ Signed: $(basename "$dylib")"
            fi
        done
    fi

    # Code signing the main bundle
    exec_cmd "Code signing ${format_name} bundle with cert: ${AppleCertName}..." \
             "codesign --deep --force --verify --verbose --options runtime --sign \"${AppleCertName}\" \"${bundle_path}\""
    green_echo "🔐 ${format_name} bundle signed."

    # Notarization
    exec_cmd "Zipping ${format_name} bundle..." "zip -r \"${zip_name}\" \"${bundle_path}\""
    exec_cmd "Submitting ${format_name} bundle for notarization..." \
             "xcrun notarytool submit \"${zip_name}\" --keychain-profile \"${NotarizationKeychainProfileName}\" --wait"
    exec_cmd "Stapling ${format_name} bundle..." "xcrun stapler staple \"${bundle_path}\""
    green_echo "🔏 ${format_name} bundle signed and notarized."

    # Clean up
    rm -rf "${zip_name}"

    return 0
}

# Function to create, sign and notarize DMG
create_sign_notarize_dmg() {
    local bundle_path="$1"
    local format_name="$2"
    local bundle_name="$(basename "${bundle_path}")"
    local dmg_name="${bundle_name%.*}"  # Remove extension
    local dmg_path="$(dirname "${bundle_path}")/${dmg_name}.dmg"
    local temp_dmg="/tmp/${dmg_name}_temp_$(date +%s).dmg"
    local staging_dir="/tmp/${dmg_name}_staging_$(date +%s)"

    echo ""
    blue_echo "Creating DMG for ${format_name}..."

    # Check if DMG already exists and is signed/notarized
    if [ -f "$dmg_path" ]; then
        blue_echo "→ DMG already exists. Checking if signed and notarized..."
        local dmg_signed=false
        local dmg_notarized=false

        if codesign --verify --deep --strict "$dmg_path" 2>/dev/null; then
            green_echo "✓ DMG is already code signed"
            dmg_signed=true
        fi

        if stapler validate "$dmg_path" 2>/dev/null | grep -q "The validate action worked"; then
            green_echo "✓ DMG is already notarized and stapled"
            dmg_notarized=true
        fi

        if [ "$dmg_signed" = true ] && [ "$dmg_notarized" = true ]; then
            green_echo "🎉 DMG already exists and is fully signed and notarized. Skipping..."
            return 0
        else
            yellow_echo "⚠ Existing DMG is not fully signed/notarized. Recreating..."
            rm -f "$dmg_path"
        fi
    fi

    # Create staging directory
    mkdir -p "$staging_dir"

    # Copy bundle to staging directory
    exec_cmd "Copying bundle to staging directory..." \
             "cp -R \"${bundle_path}\" \"${staging_dir}/\""

    # Determine plugin library path based on format
    local plugin_lib_path=""
    local link_name=""

    case "$format_name" in
        "VST3")
            plugin_lib_path="/Library/Audio/Plug-Ins/VST3"
            link_name="Install to VST3 folder"
            ;;
        "AudioUnit")
            plugin_lib_path="/Library/Audio/Plug-Ins/Components"
            link_name="Install to Components folder"
            ;;
        "Standalone App")
            plugin_lib_path="/Applications"
            link_name="Install to Applications"
            ;;
    esac

    # Create symbolic link to plugin library if path is determined
    # Symbolic links are instant and work perfectly in DMGs (unlike Finder aliases which timeout)
    if [ -n "$plugin_lib_path" ]; then
        blue_echo "→ Creating link to ${plugin_lib_path}..."

        if ln -s "$plugin_lib_path" "${staging_dir}/${link_name}" 2>&1; then
            if [ -L "${staging_dir}/${link_name}" ]; then
                green_echo "✓ Added link: $link_name"
            else
                yellow_echo "⚠ Link creation reported success but link not found"
            fi
        else
            yellow_echo "⚠ Failed to create symbolic link"
        fi
    fi

    # Create DMG with proper size calculation
    # Get size in MB and add 50MB padding to avoid "no space" errors
    local staging_size=$(du -sm "${staging_dir}" | cut -f1)
    local dmg_size=$((staging_size + 50))
    blue_echo "→ Staging directory size: ${staging_size}MB, creating ${dmg_size}MB DMG..."

    exec_cmd "Creating disk image..." \
             "hdiutil create -srcfolder \"${staging_dir}\" -volname \"${dmg_name}\" -format UDZO -size ${dmg_size}m \"${temp_dmg}\""

    # Clean up staging directory
    rm -rf "$staging_dir"

    # Sign DMG
    exec_cmd "Signing disk image with cert: ${AppleCertName}..." \
             "codesign --sign \"${AppleCertName}\" \"${temp_dmg}\""

    # Notarize DMG
    exec_cmd "Submitting disk image for notarization..." \
             "xcrun notarytool submit \"${temp_dmg}\" --keychain-profile \"${NotarizationKeychainProfileName}\" --wait"

    # Staple DMG
    exec_cmd "Stapling disk image..." "xcrun stapler staple \"${temp_dmg}\""

    # Move to final location
    exec_cmd "Moving disk image to final location..." "mv \"${temp_dmg}\" \"${dmg_path}\""

    green_echo "💿 DMG created, signed and notarized: ${dmg_path}"

    return 0
}

# Main execution
echo "=========================================="
echo "Plugin Sign & Notarize Tool (Enhanced)"
echo "=========================================="
echo ""

# Debug: Show what arguments were received
blue_echo "→ Received $# argument(s)"
if [ $# -eq 0 ]; then
    red_echo "✗ Error: No files were passed to the script"
    echo "This script should be called with file paths as arguments."
    echo "Press any key to close this window..."
    read -n 1 -s
    exit 1
fi

for i in "$@"; do
    echo "  - $i"
done
echo ""

# Check if environment variables are set
if [ -z "${AppleCertName:-}" ]; then
    red_echo "Error: AppleCertName environment variable not set"
    echo "Please ensure it's defined in ~/.zshrc"
    echo "Press any key to close this window..."
    read -n 1 -s
    exit 1
fi

if [ -z "${NotarizationKeychainProfileName:-}" ]; then
    red_echo "Error: NotarizationKeychainProfileName environment variable not set"
    echo "Please ensure it's defined in ~/.zshrc"
    echo "Press any key to close this window..."
    read -n 1 -s
    exit 1
fi

green_echo "✓ Using certificate: $AppleCertName"
green_echo "✓ Using keychain profile: $NotarizationKeychainProfileName"

# Ask user if they want DMGs created
echo "Options:"
echo "1. Sign & notarize bundles only"
echo "2. Sign & notarize bundles + create signed/notarized DMGs"
echo ""
read "create_dmg_option?Choose option (1 or 2): "

case $create_dmg_option in
    1)
        CREATE_DMGS=false
        ;;
    2)
        CREATE_DMGS=true
        ;;
    *)
        yellow_echo "Invalid option. Defaulting to bundles only."
        CREATE_DMGS=false
        ;;
esac

echo ""

# Process each selected file
for bundle_path in "$@"; do
    if [ -d "$bundle_path" ]; then
        # Determine plugin type based on extension
        if [[ "$bundle_path" == *.vst3 ]]; then
            format_name="VST3"
        elif [[ "$bundle_path" == *.component ]]; then
            format_name="AudioUnit"
        elif [[ "$bundle_path" == *.app ]]; then
            format_name="Standalone App"
        else
            yellow_echo "Skipping: $bundle_path (not a VST3, Component, or App bundle)"
            continue
        fi
        
        echo "Processing: $(basename "$bundle_path")"
        echo "----------------------------------------"
        
        # Sign and notarize the bundle
        if sign_and_notarize_bundle "$bundle_path" "$format_name"; then
            green_echo "✓ Successfully processed: $(basename "$bundle_path")"
            
            # Create DMG if requested
            if [ "$CREATE_DMGS" = true ]; then
                if create_sign_notarize_dmg "$bundle_path" "$format_name"; then
                    green_echo "✓ DMG created for: $(basename "$bundle_path")"
                else
                    red_echo "✗ Failed to create DMG for: $(basename "$bundle_path")"
                fi
            fi
        else
            red_echo "✗ Failed to process: $(basename "$bundle_path")"
        fi
        echo ""
    else
        yellow_echo "Skipping: $bundle_path (not a directory)"
    fi
done

echo "=========================================="
green_echo "Process complete!"
if [ "$CREATE_DMGS" = true ]; then
    echo "📁 DMG files have been created in the same directory as the original bundles"
fi
echo "Press any key to close this window..."
read -n 1 -s
SCRIPT_CONTENT

chmod +x "$SCRIPT_FILE"

# Build arguments list properly
ARGS_LIST=""
for arg in "$@"; do
    # Properly escape single quotes in the path
    escaped_arg="${arg//\'/\'\\\'\'}"
    ARGS_LIST="$ARGS_LIST '${escaped_arg}'"
done

# Open Terminal and run the script with properly quoted arguments
osascript -e "tell application \"Terminal\"
    activate
    do script \"'$SCRIPT_FILE'$ARGS_LIST; rm -f '$SCRIPT_FILE'\"
end tell"