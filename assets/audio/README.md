# Placeholder sound effects (FILLER)

These `.wav` files are programmer-synthesized placeholders, not final audio:

- `place.wav` — a tile being placed (a short clack)
- `draw.wav`  — drawing a tile from the boneyard
- `win.wav`   — winning a round/match (a small arpeggio)

To replace: drop in new files with the **same names** (any short WAV/OGG works).
`scripts/ui/game.gd` loads them by name in `_build_audio()` and skips any that
are missing, so the game still runs without audio. No code changes needed to
reskin the sound — same philosophy as the visual TileTheme.
