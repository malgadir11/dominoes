# Dominoes — project context for Claude Code

This file orients any Claude Code session (e.g. when continuing on a different
machine). Read it first; it captures decisions and state that aren't obvious
from the code alone.

## What this is
A **premium dominoes game for Steam, priced ~$5** (buy-once: no microtransactions,
energy timers, or grind). Built in **Godot 4 + GDScript**. A possible Roblox port
may come later, but Steam is the focus. The owner is migrating development from a
Mac to a **Windows desktop** (better for native Steam builds).

## Decisions already made (do not relitigate)
- **Engine:** Godot 4, GDScript. Chosen over Unity for 2D fit + MIT license.
- **Core ruleset:** Block/Draw dominoes, double-six set. BOTH variants ship as a
  match toggle (default Draw).
- **Main menu (planned), 5 options:** Multiplayer, Host Lobby, Play vs Bots,
  Tutorial, Settings. **Play vs Bots is being built first.**
- **Players:** single-player vs bots first; tuned for 2 players; design must extend
  to **2–4 players and a 2v2 multiplayer mode** later. (All those modes share ONE
  line of play, so the board rendering already generalizes.)
- **Art:** modern-minimal, flat. Everything visual is FILLER for a future artist
  and must stay easily replaceable — see the theme note below.

## Architecture (keep this separation)
Pure rules logic is headless and fully tested; presentation is separate.

```
scripts/core/    Rules engine — no nodes, no graphics, unit-tested
  tile.gd, deck.gd, hand.gd, board.gd, move.gd, round.gd, round_result.gd
scripts/ai/
  bot.gd         One evaluation function + per-tier weights (Easy/Medium/Hard/Expert)
scripts/ui/
  tile_theme.gd  ALL art params (colors, sizes, optional textures) in one Resource
  tile_view.gd   The ONLY place a tile is drawn; reads tile_theme
  board_layout.gd Serpentine (snaking) board geometry — pure, player-count agnostic
  game.gd        Play-vs-Bots screen, built in code (setup → board → match loop)
scenes/game.tscn Main scene (root Control + game.gd)
tests/           Headless test runners (see below)
```

**Art swappability (a hard requirement):** gameplay code never reads appearance.
To reskin, edit `tile_theme.gd` (or assign body/pip/back textures, or make a
`.tres` and set it on the Game node's `tile_theme`). No logic changes. Keep it
this way — placeholders are clearly marked FILLER.

## Current status
Playable **Play vs Bots**: click-to-play (auto-places when only one legal spot;
when a tile fits both ends you click the lit chain-end or an action-bar button to
choose the route). Board **snakes** within a flexible width (`board_max_width`,
auto-caps to window). Doubles render **crosswise**. The forced opening double is
**auto-played** so the board always starts with a centered tile. Match to 75.

Build order: 1) data model ✅ 2) round engine ✅ 3) AI ✅ 4) match layer (inline in
UI for now) ✅ 5) rendering/input ✅ 6) main menu (only Play-vs-Bots) 7) settings.

## AI notes
- Fair info only — the bot never peeks at hidden tiles. Difficulty = competence.
- One evaluation (`_eval_move`) shared by all tiers; tiers differ by weights +
  noise. Features: pip unload, flexibility, probabilistic denial (EXPECTED
  opponent answers, using live voids + hand-size density), void steering
  (`w_infer`, with a forced-pass bonus for covering both ends), double shedding.
- **Void inference reads passes AND draws** (`Round.history` logs draw events —
  public info). Staleness rule: a later draw on other ends may fill a void, so
  only voids re-proven by every subsequent draw stay live (bot.gd `_opponent_voids`).
- **EXPERT has a perfect endgame solver** (scripts/ai/endgame.gd): in 2P DRAW,
  once the boneyard is dry, unseen == the opponent's exact hand → alpha-beta
  solves the rest of the round exactly (trigger: unseen.size() == opp hand size;
  node budget with heuristic fallback).
- `Bot.rank_moves(r, player)` returns all legal moves best-first with a human
  "why" per move — powers both choose_move and the UI's Coach mode.
- EXPERT also runs a **sampled 2-ply lookahead** in tightened DRAW rounds
  (hypothesize void-consistent opponent hands, score their best reply) and
  **stakes-scaled denial** when the opponent is short-handed. Both are gated to
  DRAW — measured as pure noise/harmful in BLOCK (sleeping tiles dilute
  hypotheses; blocked endings punish sacrificed pips). Judge weight changes by
  tournament, never vibes.
- Measured (match win rates to 75): Hard>Easy ~92%, Medium>Easy ~93%,
  Hard>Medium ~56% (block); **Expert>Hard 57% block, 69-72% draw**.
  Assertions live in test_ai.gd.
- **No tier above Expert** (decided July 2026): dominoes' luck floor compresses
  top-end gaps — a 5th tier would measure ~55% vs Expert, imperceptible to
  players. Strength goes INTO Expert (it's also the Coach brain). For a "boss"
  feel later, use format instead: longer matches (first-to-150) amplify skill.

## Coach mode (guided play)
Setup screen toggle ("Coach"). An independent EXPERT bot ranks the player's
options each turn: the best hand tile gets the theme's `coach_color` border and
`_coach_label` shows "Coach: play [a|b] — <why>". While choosing an end for a
two-way tile, the better END tile is coach-marked and named. All explanation
text comes from bot.gd (`_compose_why` / `_solved_why`), so it's headless-tested.

## Running it
From the project folder:
- Play the game:           `godot --path .`   (Windows: use `godot.exe`)
- Run a test suite:        `godot --headless --script res://tests/test_core.gd`
  (suites: test_core, test_round, test_ai, test_layout, test_game_ui — ~51 tests)
- **Gotcha:** after adding any new `class_name` script, run
  `godot --headless --editor --quit` ONCE first so Godot registers the globals,
  otherwise headless `--script` runs fail with "Identifier not declared".

## What's likely next (owner's choice)
- 3–4 player / 2v2 support (board ready; this is seating + hand layout).
- Real main menu (wire the 5 screens).
- Polish (corner art for snake turns, placement animations, sound).
- Make Expert measurably tougher (shallow look-ahead).

## Conventions
- Build rules logic pure/headless and test it before wiring UI.
- Keep all appearance behind `tile_theme`. Mark placeholder art FILLER.
- Static-typed GDScript; short doc-comments on public methods.
