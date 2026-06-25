# Dominoes

A premium block/draw dominoes game for Steam, built in Godot 4. Starting with
single-player vs bots.

## Project layout

```
scripts/core/      Pure rules logic — no graphics, fully testable
  tile.gd            A single domino tile (unordered pip pair)
  deck.gd            The 28-tile set / boneyard (build, shuffle, draw)
  hand.gd            A player's held tiles and what they can legally play
  board.gd           The played chain and its two open ends
  move.gd            A candidate play (a tile + which end to attach it to)
  round.gd           One round: deal, turn loop, draw/pass, end, scoring
  round_result.gd    Outcome of a round (winner, type, score, pip totals)
scripts/ai/
  bot.gd             Difficulty-tiered opponent (one eval fn, per-tier weights)
tests/
  test_core.gd       Headless tests for Tile, Deck, Hand
  test_round.gd      Headless tests for Board, Move, Round
  test_ai.gd         Bot legality, inference, and a tier win-rate tournament
```

## Build order

1. **Core data model** — Tile, Deck, Hand — done
2. **Round engine** — deal, turn loop, draw/pass, round end, scoring — done
3. **AI** — evaluation function, difficulty tiers (Easy/Medium/Hard/Expert) — done
4. Match layer — rounds to a target score
5. Rendering & input (next: a playable board)
6. Main menu (Multiplayer, Host Lobby, Play vs Bots, Tutorial, Settings)
7. Settings

## Running the tests

Install Godot 4, then from this folder:

```
godot --headless --script res://tests/test_core.gd
godot --headless --script res://tests/test_round.gd
```

All tests should report `PASS` and exit with `Failed: 0`. If you add new
`class_name` scripts, run `godot --headless --editor --quit` once first so Godot
registers them before running a test.
