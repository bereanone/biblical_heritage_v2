# Bible App Sync Architecture

## 1. Static App Data

Static app data ships with the app and does not sync.

Examples:

- Bible text
- Books, chapters, verses
- Headings
- Acrostics
- Strong’s/interlinear base data
- Public-domain commentary base data
- Lexicons
- Concordance base data

Suggested database:

```text
bible_base.db
```

## 2. Synced User Study Data

User-created study data should sync between the user’s own devices.

Examples:

- Reading history
- Search history
- Memory lists and memorization progress
- Highlights
- Underlines
- Notes
- Bookmarks
- #tag lists
- $tag lists with notes and images
- @tag/group notes, if added later
- Tag groups
- Presentation lists
- Imported/exported shared lists
- Media asset records

Suggested database:

```text
user.db
```

Every syncable record should include:

```text
created_at_utc
updated_at_utc
deleted_at_utc
device_id
change_id or revision
```

Use soft deletes so other devices can learn that a record was deleted.

## 3. Local-Only Device Preferences

Device-specific settings should not sync.

Examples:

- Font size
- Theme
- Night/day mode
- Scholar/interlinear/paragraph mode state
- Line spacing
- Layout
- Orientation
- External display settings
- Presentation aspect ratio
- Audio output
- Cache state
- Selected verse
- Temporary filters

Suggested database:

```text
local_settings.db
```

## 4. Cloud Folder Structure

Use a shared cloud folder for assets and sync exchange files.

Suggested structure:

```text
BiblicalHeritage/
  ResearchLibrary/
  Concordance/
  Images/
  SharedLists/
  Sync/
```

Images should live in the cloud Images folder. The database should store only metadata:

```text
media_id
relative_path
caption
sha256_hash
mime_type
created_at_utc
updated_at_utc
deleted_at_utc
```

## 5. Sync Method

Do not sync a live cloud SQLite database directly.

Each device should keep its own local working database and synchronize through:

```text
change logs
manifests
export packages
periodic snapshots
```

Use:

```text
UTC timestamps
device_id
change_id
revision numbers
soft deletes
freshest-wins conflict handling where appropriate
```

## 6. $tag Lists

Do not sync a whole $tag list as one large object.

Sync each $tag item separately so changes from multiple devices can merge safely.

Possible $tag item types:

```text
scripture
note
image
heading
divider
external_file
```

This allows a list to include scriptures, notes, images, and presentation content without breaking sync.

## 7. Guiding Rule

If it represents something the user created, collected, studied, marked, tagged, memorized, imported, or shared, it belongs in synced user data.

If it represents how one specific device displays or behaves, it belongs in local-only settings.
