# MythLog Design Assets

These assets are generated production sources for the MythLog app identity and timeline filter system.

Generation mode: built-in image generation.

> **Rename status.** These files now carry MythLog-prefixed names, but the
> image content has never been redrawn through any rename. Anything with a
> wordmark still shows the original pre-release name: the branding hero art,
> the App Store screenshots, and `AppStore/MythLog-Privacy-Policy.pdf` (whose
> `/Title` metadata and body text are both stale). The app icon and the
> timeline filter glyphs contain no text and carry over as-is. Regenerating the
> wordmarked assets is tracked in `HUMAN_CHECKLIST-RENAME.md`; a visual rebrand
> is out of scope for the rename itself.

Source set:

- `AppIcon/MythLog-AppIcon-Source.png`: original high-resolution generated app icon source.
- `AppIcon/MythLog-AppIcon-1024.png`: normalized 1024px macOS app icon master.
- `AppIcon/MythLog.icns`: packaged macOS app icon.
- `TimelineFilters/*.png`: high-resolution generated filter glyph artwork for future UI use, docs, installer art, and template previews.

Prompt direction:

- Minimal production macOS security utility identity.
- Dark-first visual system.
- Shield, alarm, ledger, lock, notification, heartbeat, network, backup, file, and filter-control motifs.
- High-contrast teal, blue, graphite, white, and restrained accent colors.
- No text inside generated artwork.
