# StudyBible development instructions

## Automatic correction workflow

Whenever the user reports a text, pronunciation, narration, reader-navigation,
scroll-follow, or content-update defect, automatically start the cross-platform
correction workflow in `docs/content-correction-workflow.md` as part of that
same repair. Do not wait for a separate request to compare platforms.

Check iPhone, iPad, Android, Mac, and the Watch's applicable companion behavior.
A shared source-code fix does not establish that all installed platforms display
or play it correctly. Explicitly report any platform or runtime path not verified.

Preserve the user's originals, notes, annotations, bookmarks, reading positions,
settings, accepted narrator identities, and unrelated local changes. Never
uninstall an app or reset its data to make a correction appear successful.

Complete the already authorized repair while adding the workflow evidence.
Do not create recurring polling jobs or extra chats merely to follow this rule.

Audio repairs must match the user-approved narrator and surrounding delivery.
Do not introduce volume jumps, abrupt joins, altered surrounding pauses, or cue
misalignment. Keep existing surrounding timing intact; any unavoidable timing
change needs explicit review before promotion. Verify a before/repair/after
context sample, and keep automated measurements distinct from user listening.

## Source and data storage

Keep source, tests, small manifests, and restore tools in GitHub. Large app data
is checksum-versioned in the private Google Drive project; see docs/cloud-data.md
and data/cloud-data-20261102.json. Restore required ignored inputs before builds
or data-dependent tests. OneDrive is for long-term archives. Verify cloud copies
before reclaiming local data, and preserve installed-app data and active workers.
