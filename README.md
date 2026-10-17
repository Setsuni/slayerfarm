# Slayer Farm

A MacroQuest Lua script that works through EverQuest **Slayer achievements** for you. It reads your Slayer progress, picks the zones that cover the most unfinished achievements, travels your group there, and hunts only the mobs that count.

> **Live servers only.** Not built for or tested on EMU servers.

## Features

**Achievements tab**
- Reads every Slayer achievement live from the game, with progress bars, grouped under the parent achievement (Progressive, Highly Decorated, A Force of Nature).
- Achievements with several objectives (like *I'm a People Person!*) are broken out into objective rows, and only unfinished objectives are hunted.
- Optional achievements are greyed out and left out of farming unless you tick them.
- Shows which mob types count. Click one to search it on Allakhazam.
- Suggests zones for each achievement, filtered to the expansions you own. Instanced suggestions (LDoN) are shown as manual.

**Farm tab**
- **Auto mode** ranks zones by how many of your unfinished achievements they cover, so one trip works on several. Or pick a zone yourself.
- **Brings your group**: broadcasts `/travelto` over DanNet, waits for everyone, then puts followers on `/boxr chase`.
- Shows what you're working on in the zone, what mobs it's looking for, your current target and its race, and Slayer kills per hour.
- Moves to the next zone by itself when everything in the current one is done.

**Hunter**
- Picks targets by race and body type, not by name, and always handles anything aggroed on you first.
- With *Kill anything* on, mobs that count still come first.
- Uses real walking path length to choose the nearest mob, skips mobs other players are near, rests when the group is low, and gets itself unstuck.
- Per-zone ignore list, with automatic ignoring of mobs that don't take damage.
- Draws the hunt radius on the in-game map.
- Learns as it goes: when a kill raises an achievement count, it remembers that race.

**Table Flipper** is handled too: in Undershore it opens the *budding mindspore* objects instead of hunting.

## Requirements

- [MacroQuest](https://www.macroquest.org/) (Live)
- **MQ2Nav** with meshes for the zones you farm
- **MQ2EasyFind** for `/travelto`
- **MQ2Boxr** plus a combat plugin it supports (CWTN class plugins, RGMercs, etc.). Your combat plugin does the fighting; Slayer Farm handles movement and targeting.
- **MQ2DanNet**, only needed to bring a group

## Install

1. Copy this folder into your MacroQuest `lua` folder as `lua\slayerfarm`.
2. In game: `/lua run slayerfarm`

## Commands

| Command | What it does |
|---|---|
| `/sf show` / `/sf hide` | Open or close the window |
| `/sf start` | Start farming |
| `/sf pause` / `/sf resume` | Pause or resume hunting |
| `/sf stop` | Stop farming (the script keeps running) |
| `/sf next` | Skip to the next zone |
| `/sf ignore` | Never hunt mobs with your target's name in this zone |
| `/sf scan` | Rescan achievements |
| `/sf dump` | Write the Slayer category to `config\slayerfarm_dump.txt` for bug reports |
| `/sf quit` | Stop farming and end the script (also `/sf end`, `/sf exit`) |

Use `/sf quit` rather than `/lua stop slayerfarm`, so navigation stops and settings are saved first.

## Files

Settings are saved in your MacroQuest `config` folder:
- `slayerfarm_<server>_<character>.lua`: your options, per character
- `slayerfarm_ignores.lua`: per-zone ignore lists, shared by all characters
- `slayerfarm_learned.lua`: races learned from kills, shared by all characters

## Known limits

- MQ can only detect expansions up to Underfoot. If you own all of those, Slayer Farm assumes you own everything. Pick your expansion in the dropdown if that's wrong.
- Zone suggestions come from community data and are best effort. Some mob types use plain-English names that may not match the game's race names exactly; the learning feature fills those gaps over time.

## Credits

- Achievement, mob and zone data from [Bonzz's Slayer page](https://www.bonzz.com/slayerach.htm), [Allakhazam](https://everquest.allakhazam.com/) comments, and EverQuest Nexus.
- Hunting inspired by MultiHunter by Nerp (priority system by knave23). Slayer Farm's hunter is a separate rewrite.

## License

MIT. See [LICENSE](LICENSE).
