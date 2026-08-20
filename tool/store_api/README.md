# Store API status scripts

Read-only scripts to check Play Console / App Store Connect release status
without navigating the web consoles. Credentials live outside this repo at
`~/.config/studybible2-release-api/` — never commit them.

## Google Play Developer API

1. In [Google Cloud Console](https://console.cloud.google.com/), create (or pick) a project.
2. Enable the **Google Play Android Developer API** for that project (APIs & Services → Library).
3. Create a service account (IAM & Admin → Service Accounts → Create Service Account). No roles needed at the Cloud project level.
4. Open the service account → Keys → Add Key → Create new key → JSON. This downloads a `.json` file — **do not put it in this repo.**
5. Move it to: `~/.config/studybible2-release-api/play-service-account.json`
6. In [Play Console](https://play.google.com/console) → Users and permissions → Invite new users, invite the service account's email (found in the JSON as `client_email`) with at minimum **View app information (read-only)** permission for the "Biblical Heritage #StudyBible" app.
7. Run:
   ```
   ~/.config/studybible2-release-api/venv/bin/python3 tool/store_api/play_console_status.py
   ```

## App Store Connect API

1. In [App Store Connect](https://appstoreconnect.apple.com/) → Users and Access → Integrations → App Store Connect API.
2. Generate a new key. Role: **Developer** or **App Manager** is sufficient for read-only status checks (avoid Admin unless you need it for more later).
3. Note the **Key ID** and **Issuer ID** shown on that page.
4. Download the `.p8` private key file — **this can only be downloaded once**, so save it immediately to: `~/.config/studybible2-release-api/asc_private_key.p8`
5. Save the two IDs as plain text files:
   ```
   echo -n "YOUR_KEY_ID" > ~/.config/studybible2-release-api/asc_key_id.txt
   echo -n "YOUR_ISSUER_ID" > ~/.config/studybible2-release-api/asc_issuer_id.txt
   ```
6. Run:
   ```
   ~/.config/studybible2-release-api/venv/bin/python3 tool/store_api/app_store_connect_status.py
   ```

## What these scripts do (and don't do)

Both scripts only **read** status — app info, tracks, builds. Neither one
submits, rolls out, or publishes anything. Any future script that *does*
take a publishing action will always be run with your explicit go-ahead,
never automatically.
