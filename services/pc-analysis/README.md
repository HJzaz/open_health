# Private Windows analysis for the iPhone app

The iPhone sends a consistent SQLite snapshot and its saved demographic profile to
your own Windows PC. The PC uses the same Rust/Python analysis pipeline as the web
dashboard and sends the shared JSON report back. The ring authentication key never
leaves the phone. No paid analysis API is used.

## Setup

1. Download **OpenHealth-Windows-analysis** from the successful **Build Windows
   analysis service** Actions run and extract it to a folder on your PC.
2. Install Python 3.11 or later with the Windows Python launcher. Install Tailscale
   on the PC and iPhone, signed into the same private network.
3. Double-click **Start-Analysis.cmd**. Keep that window open. It prints a private
   connection code, which changes whenever you restart the service.
4. In an Administrator PowerShell window run:

   ```powershell
   tailscale serve --bg http://127.0.0.1:8765
   ```

   Follow Tailscale's HTTPS enablement link if prompted. Copy its HTTPS address,
   such as `https://my-pc.my-tailnet.ts.net`. Serve is private to your tailnet.
   **Do not enable Funnel, port forwarding, or public hosting.** If you already
   use Serve on this PC, inspect `tailscale serve status` before changing its route.
5. Install the updated iPhone IPA over the existing app using the same signing
   account and bundle ID. Do not delete the app or reset the ring.
6. Open the **computer icon** at the top of the iPhone home screen. Enter the HTTPS
   address and PC connection code, then tap **Test connection**.
7. Check/save your real age, sex, height, weight and ring size in Profile. The
   upstream app initially uses defaults; those are not verified personal values.
8. Sync the ring, then tap **Send ring data and analyze** in PC analysis. Keep the
   app open until it receives the report. Allow up to five minutes.

The PC must be awake and connected. The service binds only to 127.0.0.1 and requires
a connection code even over Tailscale. The app rejects HTTP URLs and redirects.
The code is stored in the iPhone Keychain separately from the ring's key. No health
uploads or credentials are written to access logs. Snapshots and PC reports are
held in temporary files while processing and deleted afterward (ordinary deletion,
not a forensic secure erase). The returned report stays on the phone until deleted
from the PC analysis screen. Stop the service by closing its terminal window.

Official Tailscale documentation:
https://tailscale.com/docs/features/tailscale-serve
https://tailscale.com/docs/reference/examples/serve

## What analysis is actually available

- Shared nightly HR/HRV/temperature/oxygen and activity summaries, where recorded.
- Desktop signal-based sleep-stage **estimates** when no trained model is present.
  The upstream report labels these with `staging_source: signals`.
- Sleep-derived statistics only when the underlying signals/staging have enough
  coverage. Fresh reset rings may have no night available yet.
- Optional desktop Python runners are included, but **proprietary/private model
  weights are not included or downloaded**. Merely connecting the service does not
  enable cardiovascular-age, illness or automatic-workout models.

The iPhone's PC report is a timestamped snapshot, not the live dashboard. Open a day
in it to view the existing sleep/activity reports. The same calculations and JSON
are used by the desktop web dashboard. No clinical validation is claimed, and the
PC service cannot recreate measurements that the ring never captured.

If you already lawfully have compatible model weights, use the upstream documented
model setup locally; never commit weights, databases, profiles, codes or ring keys
to the public repository. Installing a language model alone does not supply a
validated sleep-staging model.

## Developer checks

`python -m unittest discover -s services/pc-analysis -p test_server.py -v`

The `oura analyze --tz-offset 3 --db exported.db` command is offline and requires
no ring key. Gateway tests exercise authentication, invalid payloads, concurrency,
subprocess invocation and temporary-data cleanup. Native Windows compilation is
checked by Actions; end-to-end iPhone-to-PC connectivity must be tested on your
own devices after setup.
