# Chore Blitz redesign (Nov 2026)

Mockups: `phone-today-howto-settings.png`, `phone-game-mode-loot-chest.png`,
`tv-board.png`, `tv-board-game-mode.png` (source: `mockups.html`).

## Identity
- Navy + lightning yellow. Rounded heavy type for titles (`.rounded`), monospaced black in arcade.
- Colors live in `Shared/Theme.swift` (`Palette`, `Skin`). Light and dark both supported on the phone; TV is always dark.
- Accent `#FFC83D` (dark text on it), done green `#3DDC84`.
- People: Brandon `#3B8CFF`, Kira `#F0569A`, Braden `#34C77B`, Reagen `#FF9534`.
- Arcade (Game mode): background `#0F0524 → #2A0D45`, yellow `#FFE14D`, cyan `#3DE0FF`, mint `#5DFFC1`, pink `#F0569A`, chest violet `#6B3FD4`, square 6pt corners, hard drop shadows.

## Phone
- Three tabs: Today, Chores, Settings. Everything that was hidden in the avatar menu is in Settings.
- Today (list running): progress card with a bar segmented by who did each chore; "Your chores" as big cards with How to + a large Done; "Up for grabs" rows with Claim; others; done.
- Chore how-to: checklist steps and one big sticky action button.
- Today (nothing running): last time's results, earnings, and "Make today's list" for parents.
- Arcade look is a per-phone setting (on by default only for Reagen).

## TV
- One grid of every chore in list order; a chore changes state in place (open: bright; in progress: person color bar + avatar; done: dimmed, struck through, check).
- Right panel: one lane per person with what they're on and their done count (XP in Game mode).
- Header: big count, person-colored segmented bar, timer when Blitz mode is on. Game mode swaps the bar for LV + XP.

## Game mode rules changed
- Unopened chests carry over when the TV is cleared or a new list starts.
- Parents pay everything owed with one button.
- TV music has its own switch.
- Wording: "loot chest" / "Open", not "spin".
