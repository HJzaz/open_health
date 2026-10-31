# Install Open Health on an iPhone using Windows

This fork can build an **unsigned iPhone IPA on GitHub's macOS runner**.
No local Mac or Oura API credentials are required to build it.
An unsigned IPA still needs Apple signing before it can run on an iPhone.

## Download the build

1. Open this repository's **Actions** tab and choose **Build iPhone IPA**.
2. Open the successful run for the `codex/iphone-sideload` branch.
3. Download **OpenHealth-iPhone-unsigned** under Artifacts (sign in to GitHub).
4. Extract the downloaded ZIP on Windows. Inside are `OpenHealth-unsigned.ipa`
   and `SHA256SUMS.txt`. The IPA itself is the app package; do not extract it.

After this workflow is on the default branch, **Run workflow** can build it again.
Until then, pushing changes to `codex/iphone-sideload` starts it automatically.
A failed run produces no installable IPA; inspect the failed step or build-log artifact.

## Sign and install from Windows

Use AltStore Classic/AltServer's official Windows installation instructions:
https://faq.altstore.io/altstore-classic/how-to-install-altstore-windows

Install AltStore on your iPhone with AltServer on Windows, then open the IPA in
AltStore to sign and install it. Enter Apple credentials only in the signing
tool's own interface, never in GitHub files, Actions secrets, or chat.
A free Apple account normally requires refreshing apps every seven days; check
the current AltStore instructions for requirements and limits.

Requires **iOS 17 or later**. The model-free app has direct BLE sync and local
summaries. It excludes the upstream private Torch model weights and LibTorch;
do not expect full sleep staging, cardiovascular-age or automatic activity
model output. It is not a replacement for every feature of the official app.

Apple Health export is deliberately unavailable in this personal build.
The signing project omits the HealthKit entitlement, and a build-specific
Info.plist flag blocks HealthKit authorization, writes and deletion.
Upstream CI/TestFlight builds retain their existing HealthKit configuration.

## First connection: preserve your existing ring data

Install and launch the app, grant Bluetooth access, then inspect its pairing
screen. Keep the ring nearby; placing it on its charger can help discovery.

**Do not factory-reset or unpair the ring as an installation step.** Your ring is
already set up with another app, so it may reject creation of a new pairing key.
A local Bluetooth pairing key is different from an Oura cloud API key. The app
can create and store a key for a factory-state ring, but that does not prove it
can adopt your already-paired Ring 4 without resetting it or importing its key.

Pause if the app asks for a pairing key or a factory reset. Record the displayed
error and use Help & diagnostics to inspect the connection stage. Never publish
pairing keys, raw health exports, or personally identifying diagnostics to this
public repository. A factory reset can erase unsynced ring data and requires a
separate, informed decision.

The IPA building successfully verifies compilation and packaging, **not** BLE
pairing or data accuracy. Those require testing with the actual iPhone and ring.

## Optional Windows analysis connection

Download the newer IPA and Windows analysis package from their successful Actions
runs. See `services/pc-analysis/README.md` for private Tailscale HTTPS setup.
Install the update over the existing app; do not delete it or reset your ring.
