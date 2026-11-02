# App demonstration and bug cleanup — October 18, 2026

Status: source fixes in progress. Mac Apple Silicon build and Android arm64 test package compiled. Neither installed. Video requires demo-flow verification and a human dry run.

## Records
- [[overnight-progress|Implementation and test evidence]]
- [Detailed findings and user decisions](review-findings.txt)

## Video scope
Use actual app screens and existing generated recordings; no new synthetic narration. Psalm 23 rather than Romans; day/night themes; Steps to Christ Contents, chapter playback and scripture-reader popup; EG White and Pioneer library views; create/default Sabbath hashtag; Exodus20:8–11 selection, listen/loop/scheduling; formatted note and presentation; export into Word; category filter on/off; cross references; Acts5:15–16 Greek word study, occurrences, return navigation; both interlinear styles; font size and history.

## Critical path
- Finish nonblocking feedback: no routine bars or dismiss/OK prompts. Current error-dialog substitution must be corrected to inline feedback.
- Diagnose audio handoff; logs show sequential generated introduction and saved Qwen clips but audible overlap remains unverified.
- Verify Word paste preserves note styles and real UI clears stale lexical state.
- Do not install Android until remaining demo bugs are fixed, per user.
- Dry run together, then capture/edit movie.

## Separate follow-ups
Immediate reversible moves to Trash, confirmation only for irreversible deletion/manual emptying. Setup Trash retention default seven days, extendable to month/year/never. History never expires automatically; deliberate Clear History confirms. These are not blockers for video.

This note summarizes decisions and evidence; it is not a verbatim conversation recording. This chat is not automatically transcribed into Obsidian.
