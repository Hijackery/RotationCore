# Pull request

## What & why

<!-- Describe the change and the motivation. -->

## Checklist

- [ ] `python3 RotationCore/verify.py` prints `PASS`
- [ ] New/changed spell ids verified against `https://wotlkdb.com/?spell=<id>`
- [ ] User-facing strings localised (EN base + 8 mirror files)
- [ ] No forbidden APIs (`C_*`, `loadstring`, `securecallfunction`, Ace3, external deps)
- [ ] Version bumped in `DH.Version` **and** all 11 `.toc` files (for releases)
- [ ] `CHANGELOG.md` updated (for releases)

## Testing

<!-- How did you test? In-game spec/encounter, /rc selfcheck, screenshots. -->
