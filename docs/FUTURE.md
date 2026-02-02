# Future Improvements

## DRY Refactoring Discussion (2026-02-02)

### Problem Statement

Both `boomerang-plugin` and `midi-captain-max` have duplicated Apple signing/notarization code:
- ~40 lines of keychain import code in each workflow
- Signing logic in each `build-installer.sh` script

We want to consolidate this into a reusable action, but the signing flow has sequencing constraints.

### Constraint: Bundle Signing Must Happen Before Packaging

macOS code signing rules:
1. **Bundles** (.app, .vst3, .component) must be signed with Developer ID Application **before** they go into the .pkg
2. **The .pkg itself** is signed with Developer ID Installer **after** building
3. The .pkg signature does NOT sign contents — just proves the installer's origin

Required flow:
```
1. Build unsigned bundles
2. Sign bundles        ← Developer ID Application
3. Build .pkg with signed bundles inside
4. Sign .pkg           ← Developer ID Installer  
5. Notarize .pkg
6. Staple ticket
```

Steps 2 and 3 **cannot be swapped**.

### Project-Specific vs DRY-able

| DRY-able (identical) | Project-Specific |
|---------------------|------------------|
| Keychain import | Bundle paths |
| `codesign` calls | codesign flags (`--deep` or not) |
| `productsign` calls | `pkgbuild` (identifiers, install locations) |
| `xcrun notarytool` | `productbuild` (distribution.xml, resources) |
| `xcrun stapler` | Template substitution |

### Options Considered

#### Option A: Import-Only Mode
- Action just imports certs into keychain
- Scripts call `codesign`/`productsign`/`notarytool` directly
- DRYs ~40 lines of keychain setup, keeps signing in scripts
- **Pro:** Smallest change, easy to adopt
- **Con:** Signing logic still duplicated in scripts

#### Option B: Build-Command Sandwich
- Action takes a `build-command` input
- Flow: import certs → sign bundles → **run build command** → sign pkg → notarize
- **Pro:** All signing in one place
- **Con:** Complex action, build command runs inside action context

```yaml
- uses: MC-Music-Workshop/apple-codesign-notarize@v1
  with:
    sign-bundles: |
      build/MyApp.app
      build/MyPlugin.vst3
    build-command: ./build-installer.sh  # runs after bundles signed
    package-path: build/installer/MyApp.pkg
    # certs + notarization...
```

#### Option C: Two-Phase Action Calls
- First call: import certs + sign bundles (keychain persists)
- Script builds unsigned pkg
- Second call: sign pkg + notarize + cleanup keychain
- **Pro:** Clear separation
- **Con:** Two action calls, keychain management across steps

#### Option D: Use Existing Actions for Cert Import

**Idea:** Split into modular actions:

1. Use an existing action (or create `apple-import-certificates`) for keychain setup
2. Use our action **only** for signing + notarizing (assumes certs already in keychain)

Existing actions to investigate:
- [apple-actions/import-codesign-certs](https://github.com/apple-actions/import-codesign-certs) — Apple's official
- [ssrobins/import-codesign-certs](https://github.com/ssrobins/import-codesign-certs)

This would make our action simpler — it just does sign + notarize, assumes keychain is set up.

**Workflow example:**
```yaml
# Step 1: Import certs (existing action or new simple one)
- uses: apple-actions/import-codesign-certs@v2
  with:
    p12-file-base64: ${{ secrets.MACOS_APPLICATION_CERT }}
    p12-password: ${{ secrets.MACOS_APPLICATION_CERT_PWD }}

# Step 2: Sign bundles (our action, assumes certs in keychain)
- uses: MC-Music-Workshop/apple-codesign-notarize@v1
  with:
    sign-bundles: build/MyApp.app
    
# Step 3: Build pkg (project script)
- run: ./build-installer.sh

# Step 4: Sign pkg + notarize (our action again)
- uses: MC-Music-Workshop/apple-codesign-notarize@v1
  with:
    package-path: build/installer/MyApp.pkg
    notarize: true
    apple-id: ${{ secrets.APPLE_ID }}
    # ...
```

**Pro:** Maximum modularity, reuses existing work  
**Con:** Multiple action calls, need to verify existing actions meet our needs

### Decision

**Tabled for now (2026-02-02).** Current inline code works. Will revisit when:
- Adding a third repo that needs signing
- Existing actions mature
- We have time to properly refactor both repos' build scripts

### Next Steps When Revisiting

1. Evaluate `apple-actions/import-codesign-certs` — does it meet our needs?
2. Decide: Option A (import-only) vs Option D (modular with existing actions)
3. Refactor `build-installer.sh` in both repos to remove signing code
4. Update workflows to use action(s)
5. Test thoroughly before removing old code
