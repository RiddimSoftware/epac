# Local TestFlight Build Guide

Every developer who merges to `main` must upload a TestFlight build first so the daily App Store release pipeline (EPAC-324) has a fresh build to submit. GitHub Actions no longer runs the macOS build automatically (EPAC-370) — all uploads happen locally.

The build takes **15–25 minutes** on a recent MacBook Pro. Start it before your lunch break.

---

## One-time setup

### 1. Write the App Store Connect private key

```bash
mkdir -p ~/.appstoreconnect/private_keys
aws secretsmanager get-secret-value \
  --secret-id appstore/connect-api \
  --region us-east-1 \
  --query SecretString \
  --output text \
  | python3 -c "import sys, json; print(json.load(sys.stdin)['private_key'])" \
  > ~/.appstoreconnect/private_keys/AuthKey_S6U297PQHR.p8
chmod 600 ~/.appstoreconnect/private_keys/AuthKey_S6U297PQHR.p8
```

Requires AWS CLI configured with access to the `appstore/connect-api` secret.

### 2. Add environment variables to your shell profile

Add to `~/.zshrc` (or `~/.bashrc`):

```bash
export ASC_KEY_ID="S6U297PQHR"
export ASC_ISSUER_ID="69a6de88-aaae-47e3-e053-5b8c7c11a4d1"
```

Then reload: `source ~/.zshrc`

### 3. Install the Apple Distribution certificate

The build requires the Apple Distribution certificate in your local keychain. Get the `.p12` from a teammate and import it by double-clicking the file.

To verify it's installed:
```bash
security find-identity -v -p codesigning | grep "Apple Distribution"
```

### 4. Install Bundler dependencies (once per machine)

```bash
cd ios
bundle install
```

---

## Per-PR workflow

Run this **after your changes are committed and before opening your PR**:

```bash
cd /path/to/epac-impl-X/ios
bundle exec fastlane deploy
```

Confirm success: look for `Upload Successful` near the end of the output. The build appears in App Store Connect → TestFlight within ~10 minutes after upload.

Then open your PR / merge to `main`.

---

## What `fastlane deploy` does

1. Queries TestFlight for the current maximum build number and increments it by 1
2. Downloads/creates provisioning profiles for `net.dinglebox.cabinetdoor` and `net.dinglebox.cabinetdoor.Clip` using the distribution cert in your keychain
3. Writes the profile UUIDs into the Xcode project (manual signing — avoids the 2-cert account limit)
4. Archives and signs the app in Release configuration
5. Uploads the `.ipa` to TestFlight (no external tester distribution yet)

---

## Troubleshooting

**"No certificate found" / "No matching profile"**
The Apple Distribution certificate is not in your keychain. Get the `.p12` from a teammate and import it.

**"ASC_KEY_ID not set" / `KeyError: 'ASC_KEY_ID'`**
The environment variables are missing. Run `source ~/.zshrc` or open a new terminal after adding them.

**"Build number conflict"**
Another developer uploaded a build while you were building. Re-run `bundle exec fastlane deploy` — it auto-increments past the conflicting number.

**"Two-step verification required" / 2FA prompt**
The Fastfile uses the App Store Connect API key (not your Apple ID), so 2FA should never be required. If you see this, `ASC_KEY_ID` or the `.p8` file is not set up correctly.

**"Provisioning profile not found for target epac-clip"**
Your Apple Developer account may not have access to create profiles for the App Clip. Ask the account holder to add you or share their profiles.
