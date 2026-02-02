# Apple Codesign & Notarize Action

A GitHub Action for signing and notarizing macOS packages (`.pkg`) with Apple Developer certificates.

## Features

- **Import certificates** into a secure temporary keychain
- **Sign bundles** (`.app`, `.vst3`, `.component`, etc.) with Developer ID Application
- **Sign packages** (`.pkg`) with Developer ID Installer
- **Notarize** with Apple's notary service
- **Staple** the notarization ticket for offline verification
- **Graceful degradation** — works with partial credentials
- **Secure cleanup** — removes temporary keychain after use

## Usage

### Basic Example (Sign Package Only)

```yaml
- name: Sign Package
  uses: MC-Music-Workshop/apple-codesign-notarize@v1
  with:
    installer-certificate: ${{ secrets.MACOS_INSTALLER_CERT }}
    installer-certificate-password: ${{ secrets.MACOS_INSTALLER_CERT_PWD }}
    package-path: build/MyApp-1.0.0.pkg
```

### Full Example (Sign Bundles + Package + Notarize)

```yaml
- name: Sign and Notarize
  uses: MC-Music-Workshop/apple-codesign-notarize@v1
  with:
    # Application certificate for signing .app, .vst3, etc.
    application-certificate: ${{ secrets.MACOS_APPLICATION_CERT }}
    application-certificate-password: ${{ secrets.MACOS_APPLICATION_CERT_PWD }}
    
    # Installer certificate for signing .pkg
    installer-certificate: ${{ secrets.MACOS_INSTALLER_CERT }}
    installer-certificate-password: ${{ secrets.MACOS_INSTALLER_CERT_PWD }}
    
    # Notarization credentials
    apple-id: ${{ secrets.APPLE_ID }}
    apple-app-password: ${{ secrets.APPLE_APP_PASSWORD }}
    team-id: ${{ secrets.APPLE_TEAM_ID }}
    
    # Bundles to sign (newline or space separated)
    sign-bundles: |
      build/MyApp.app
      build/MyPlugin.vst3
      build/MyPlugin.component
    
    # Package to sign
    package-path: build/MyApp-unsigned.pkg
    signed-package-path: build/MyApp.pkg
```

### Using Outputs

```yaml
- name: Sign and Notarize
  id: sign
  uses: MC-Music-Workshop/apple-codesign-notarize@v1
  with:
    installer-certificate: ${{ secrets.MACOS_INSTALLER_CERT }}
    installer-certificate-password: ${{ secrets.MACOS_INSTALLER_CERT_PWD }}
    package-path: build/MyApp.pkg

- name: Report Status
  run: |
    echo "Signed: ${{ steps.sign.outputs.signed }}"
    echo "Notarized: ${{ steps.sign.outputs.notarized }}"
    echo "Stapled: ${{ steps.sign.outputs.stapled }}"
```

## Inputs

| Input | Required | Description |
|-------|----------|-------------|
| `installer-certificate` | **Yes** | Base64-encoded Developer ID Installer certificate (`.p12`) |
| `installer-certificate-password` | **Yes** | Password for the installer certificate |
| `package-path` | **Yes** | Path to the `.pkg` file to sign |
| `application-certificate` | No | Base64-encoded Developer ID Application certificate (`.p12`) |
| `application-certificate-password` | No | Password for the application certificate |
| `apple-id` | No | Apple ID email for notarization |
| `apple-app-password` | No | App-specific password for notarization |
| `team-id` | No | Apple Developer Team ID |
| `sign-bundles` | No | Paths to bundles to sign (newline or space separated) |
| `signed-package-path` | No | Output path for signed package (default: replaces original) |
| `notarize` | No | `true`, `false`, or `auto` (default: `auto` = notarize if credentials provided) |
| `codesign-options` | No | Options for `codesign --options` flag (default: `runtime`) |
| `codesign-deep` | No | Use `--deep` flag for codesign (default: `false`) |

## Outputs

| Output | Description |
|--------|-------------|
| `signed` | Whether the package was signed successfully (`true`/`false`) |
| `notarized` | Whether the package was notarized successfully (`true`/`false`) |
| `stapled` | Whether the notarization ticket was stapled (`true`/`false`) |
| `can-sign-app` | Whether application signing certificate was available |
| `can-sign-pkg` | Whether installer signing certificate was available |
| `can-notarize` | Whether notarization credentials were available |

## Preparing Certificates

### Export from Keychain Access

1. Open **Keychain Access** on your Mac
2. Find your "Developer ID Installer" certificate
3. Right-click → **Export** → Choose `.p12` format
4. Set a strong password
5. Repeat for "Developer ID Application" certificate

### Encode as Base64

```bash
base64 -i DeveloperIDInstaller.p12 | pbcopy
# Paste into GitHub secret: MACOS_INSTALLER_CERT

base64 -i DeveloperIDApplication.p12 | pbcopy
# Paste into GitHub secret: MACOS_APPLICATION_CERT
```

### Create App-Specific Password

1. Go to [appleid.apple.com](https://appleid.apple.com)
2. Sign in → **App-Specific Passwords**
3. Generate a new password for "GitHub Actions"
4. Save as GitHub secret: `APPLE_APP_PASSWORD`

## Required Secrets

| Secret | Description |
|--------|-------------|
| `MACOS_INSTALLER_CERT` | Base64-encoded Developer ID Installer `.p12` |
| `MACOS_INSTALLER_CERT_PWD` | Password for installer certificate |
| `MACOS_APPLICATION_CERT` | Base64-encoded Developer ID Application `.p12` |
| `MACOS_APPLICATION_CERT_PWD` | Password for application certificate |
| `APPLE_ID` | Your Apple ID email |
| `APPLE_APP_PASSWORD` | App-specific password |
| `APPLE_TEAM_ID` | Your Team ID (e.g., `9WNXKEF4SM`) |

## Security

- Certificates are imported into a **temporary keychain** with a random password
- The keychain is **automatically deleted** after the action completes
- Certificate files are deleted immediately after import
- No secrets are logged

## License

MIT License - see [LICENSE](LICENSE)
