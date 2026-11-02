# StudyBible data and source storage

The application source, small configuration manifests, tests, and restore tools
belong in GitHub. Large book payloads, databases, approved audio, model files,
source datasets, and locally built narration frameworks are saved in the private
Google Drive StudyBible2 project. OneDrive is for long-term archives.

## Current data checkpoint

- Date: November 2, 2026.
- Google Drive folder: https://drive.google.com/drive/folders/1jAkLH2eG_yXbag2imc2f45Ydhd7MZkGv
- Manifest: `data/cloud-data-20261102.json`.
- Contents: every regular asset and source-data file, local package sources and
  native frameworks, plus the large audit reports removed from Git.
- Identical contents are stored once in numbered ZIP archives and a small
  supplemental evidence archive.
- Each archive and each restored file has a SHA-256 checksum in the manifest.

The source commit removes large payloads from Git tracking without deleting the
working files. Existing approved recordings, live app data, and installed apps
are unaffected. Git history is not rewritten. These are build inputs, not a
backup of a device's current notes or app settings.

## Restore a fresh checkout

Download all numbered ZIP files from the private folder above to a local folder.
Keep the files needed for a build available offline. Then run from the checkout:

```sh
python3 tool/restore_cloud_data.py --archives /path/to/downloaded-archives
python3 tool/restore_cloud_data.py --verify-only
```

The restore tool checks the required archives before writing files and checks
each restored object. It skips files already matching the checkpoint and refuses
to overwrite differing local files. Use an empty checkout or preserve differing
files separately before restoring. It never downloads from an unauthenticated
public URL or changes sharing permissions.

Normal app updates should reuse verified unchanged library/audio backup data.
Save changed notes, annotations, settings, database WAL files, and reading
positions separately. Do not repeatedly copy a complete unchanged library.

After a verified upload, build payloads may be kept only in Google Drive. Restore
them before running builds or tests that read the shipped data. Installed apps
have their own bundled data and do not read payloads from the source checkout.
