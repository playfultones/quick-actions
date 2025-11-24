# CreatePluginPackage Quick Action

A macOS Quick Action for code signing and notarizing audio plugins (VST3, AudioUnit, Standalone Apps) with Apple Developer credentials.

## Prerequisites

### 1. Apple Developer Account

You need an active Apple Developer Program membership ($99/year) to code sign and notarize applications.

- Enroll at: https://developer.apple.com/programs/

### 2. Developer Certificate

Install your Apple Developer certificate in Keychain Access:

1. Go to https://developer.apple.com/account/resources/certificates
2. Create a "Developer ID Application" certificate (for distribution outside Mac App Store)
3. Download and double-click to install in your Keychain
4. Open Keychain Access and verify the certificate exists
5. Note the full certificate name (e.g., "Developer ID Application: Your Name (TEAM_ID)")

### 3. App-Specific Password

Generate an app-specific password for notarization:

1. Go to https://appleid.apple.com
2. Navigate to Sign-In and Security → App-Specific Passwords
3. Click "Generate an app-specific password"
4. Give it a descriptive name (e.g., "Notarization")
5. Copy the generated password (format: `xxxx-xxxx-xxxx-xxxx`)

### 4. Store Notarization Credentials

Store your credentials in the macOS keychain using a profile name:

```bash
xcrun notarytool store-credentials NotarizationService \
  --apple-id "your-apple-id@example.com" \
  --team-id "YOUR_TEAM_ID" \
  --password "xxxx-xxxx-xxxx-xxxx"
```

**Parameters:**
- `NotarizationService` - The profile name (you can choose any name)
- `--apple-id` - Your Apple ID email
- `--team-id` - Your 10-character Team ID (found in developer.apple.com → Membership)
- `--password` - The app-specific password you generated

### 5. Configure Environment Variables

Add these to your `~/.zshrc` file:

```bash
# Apple Code Signing & Notarization
export AppleCertName="Developer ID Application: Your Name (TEAM_ID)"
export NotarizationKeychainProfileName="NotarizationService"
```

**To get your exact certificate name:**
```bash
security find-identity -v -p codesigning
```

After adding to `~/.zshrc`, reload it:
```bash
source ~/.zshrc
```

### 6. Verify Setup

Test that everything is configured correctly:

```bash
# Check environment variables
echo $AppleCertName
echo $NotarizationKeychainProfileName

# Verify certificate exists
security find-identity -v -p codesigning | grep "$AppleCertName"

# Test notarization credentials
xcrun notarytool history --keychain-profile "$NotarizationKeychainProfileName"
```

## Setting Up as a Quick Action

### Method 1: Automator (Recommended)

1. **Open Automator**
   - Applications → Automator
   - Click "New Document"

2. **Create Quick Action**
   - Select "Quick Action" (or "Service" on older macOS versions)
   - Click "Choose"

3. **Configure Workflow Settings**
   - "Workflow receives current": **files or folders**
   - "in": **Finder.app**
   - Check: "Output replaces selected text" (optional)

4. **Add Run Shell Script Action**
   - Search for "Run Shell Script" in the actions list
   - Drag it to the workflow area

5. **Configure Shell Script**
   - Shell: `/bin/bash`
   - Pass input: **as arguments**
   - Paste this code:
   ```bash
   /path/to/CreatePluginPackage.sh "$@"
   ```
   - **Important:** Replace `/path/to/` with the actual location of your script

6. **Save the Quick Action**
   - File → Save (⌘S)
   - Name: "Sign & Notarize Plugin"
   - Location: `~/Library/Services/` (default)

### Method 2: Services Menu Folder

Alternatively, place the Quick Action directly:

1. Navigate to: `~/Library/Services/`
2. Place your `.workflow` bundle there
3. It will appear in the Services menu

## Using the Quick Action

### From Finder

1. **Select Plugin Bundles**
   - Select one or more `.vst3`, `.component`, or `.app` files in Finder
   - Right-click (or Control+click)

2. **Run Quick Action**
   - Navigate to: Quick Actions → Sign & Notarize Plugin
   - A Terminal window will open automatically

3. **Choose Options**
   - Option 1: Sign & notarize bundles only
   - Option 2: Sign & notarize bundles + create DMG installers

4. **Wait for Completion**
   - The script will:
     - Check if already signed/notarized (skips if done)
     - Sign dylibs in Frameworks directory (inside-out signing)
     - Sign the main bundle
     - Submit to Apple for notarization
     - Staple the notarization ticket
     - Optionally create signed/notarized DMG files

5. **Press Any Key to Close**
   - When complete, press any key to close the Terminal window

## What the Script Does

### Bundle Processing

1. **Pre-check**: Verifies if bundle is already signed and notarized
2. **Inside-out Signing**: Signs dylibs in `Contents/Frameworks/` first
3. **Bundle Signing**: Signs the main bundle with hardened runtime
4. **Notarization**: Zips, submits to Apple, waits for approval
5. **Stapling**: Attaches notarization ticket to bundle

### DMG Creation (Optional)

1. **Staging**: Copies bundle to temporary directory
2. **Symbolic Links**: Adds installation links:
   - VST3 → `/Library/Audio/Plug-Ins/VST3`
   - AudioUnit → `/Library/Audio/Plug-Ins/Components`
   - Standalone → `/Applications`
3. **Image Creation**: Creates compressed DMG with proper sizing
4. **DMG Signing**: Signs the DMG file
5. **DMG Notarization**: Submits DMG for notarization
6. **DMG Stapling**: Attaches ticket to DMG

## Supported Plugin Formats

- **VST3** (`.vst3`) - Virtual Studio Technology 3
- **AudioUnit** (`.component`) - Apple's audio plugin format
- **Standalone App** (`.app`) - Standalone application

## Troubleshooting

### Environment Variables Not Found

**Error**: "AppleCertName environment variable not set"

**Solution**:
- Ensure variables are in `~/.zshrc`
- Run `source ~/.zshrc` in your current terminal
- Close and reopen Terminal completely

### Certificate Not Found

**Error**: Code signing fails with certificate errors

**Solution**:
- Run: `security find-identity -v -p codesigning`
- Copy the exact certificate name
- Update `AppleCertName` in `~/.zshrc`

### Notarization Fails

**Error**: "Error: Profile not found"

**Solution**:
- Run: `xcrun notarytool store-credentials` again
- Ensure profile name matches `NotarizationKeychainProfileName`
- Verify with: `xcrun notarytool history --keychain-profile "$NotarizationKeychainProfileName"`

### Quick Action Not Appearing

**Solution**:
- Check: System Preferences → Extensions → Finder
- Ensure your Quick Action is enabled
- Restart Finder: Option+Right-click Finder icon → Relaunch

### Script Permission Denied

**Solution**:
```bash
chmod +x /path/to/CreatePluginPackage.sh
```

## Advanced Configuration

### Custom Profile Names

If you used a different profile name when storing credentials:

```bash
# In ~/.zshrc
export NotarizationKeychainProfileName="YourCustomProfileName"
```

### Multiple Certificates

If you have multiple Developer ID certificates, specify the exact one:

```bash
# List all certificates
security find-identity -v -p codesigning

# Use the full name in ~/.zshrc
export AppleCertName="Developer ID Application: Company Name (TEAM123456)"
```

### Debug Mode

Enable verbose output:

```bash
TRACE=1 /path/to/CreatePluginPackage.sh /path/to/plugin.vst3
```

## Security Notes

- App-specific passwords are stored securely in macOS Keychain
- The script never exposes passwords in logs or output
- Certificate private keys remain in Keychain Access
- Notarization happens through Apple's secure servers

## Resources

- [Apple Notarization Documentation](https://developer.apple.com/documentation/security/notarizing_macos_software_before_distribution)
- [Code Signing Guide](https://developer.apple.com/support/code-signing/)
- [notarytool Documentation](https://developer.apple.com/documentation/security/notarizing_macos_software_before_distribution/customizing_the_notarization_workflow)

## License

MIT License. Copyright (c) 2025 Bence Kovács / Playful Tones
