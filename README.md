# Slayer Farm

A MacroQuest Lua script that works through EverQuest **Slayer achievements** for you. It reads your Slayer progress, picks the zones that cover the most unfinished achievements, travels your group there, and hunts only the mobs that count.


> **Live servers only.** Not built for or tested on EMU servers.
<img width="946" height="617" alt="image" src="https://github.com/user-attachments/assets/96e49712-ba05-49c1-8c8c-089c4ffa5814" />
<img width="946" height="820" alt="Screenshot 2026-10-17 111402" src="https://github.com/user-attachments/assets/45ee9bb0-4a26-40b8-b086-bfcec1e5a64c" />

## Features

**Achievements tab**
- Reads every Slayer achievement live from the game, with progress bars, grouped under the parent achievement (Progressive, Highly Decorated, A Force of Nature).
- Achievements with several objectives (like *I'm a People Person!*) are broken out into objective rows. Only unfinished objectives are hunted, and zone suggestions follow the races you still need.
- Optional achievements are greyed out and left out of farming unless you tick them.
- Shows which mob types count. Click one to search it on Allakhazam.
- Suggests zones for each achievement, filtered to the expansions your account owns (detected automatically, or pick one in the dropdown). Instanced suggestions (LDoN) are shown as manual.

**Farm tab**
- **Auto mode** ranks zones by how many of your unfinished achievements they cover, so one trip works on several. Or pick a zone yourself.
- **Brings your group**: broadcasts `/travelto` over DanNet, waits for everyone, then puts followers on `/boxr chase`.
- Shows what you're working on in the zone with progress and **+N this session** for each achievement, what mobs it's looking for, and your current target and its race.
- **Slayer kills** and the rate per hour only count kills that counted toward an achievement you're farming.
- Moves to the next zone by itself when everything in the current one is done.

**Hunter**
- Picks targets by race and body type, not by name, and always handles anything aggroed on you first.
- With *Kill anything* on, mobs that count still come first.
- Uses real walking path length to choose the nearest mob, skips mobs other players are near, rests when the group is low, and gets itself unstuck.
- Per-zone ignore list. Ignoring your current target moves on immediately, and mobs that don't take damage are ignored automatically.
- Drops a mob it's walking to as soon as it stops counting (for example, when you finish that achievement).
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

1. Put the files in your MacroQuest `lua` folder as `lua\slayerfarm`. Either:
   - `git clone https://github.com/Setsuni/slayerfarm.git` from inside your `lua` folder, or
   - **Code > Download ZIP**, extract it, and rename the folder from `slayerfarm-main` to `slayerfarm`.
2. In game: `/lua run slayerfarm`

The folder must be named `slayerfarm`, or the script can't load its files.

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

- Zone suggestions come from community data and are best effort. Some mob types use plain-English names that may not match the game's race names exactly; the learning feature fills those gaps over time.

## Credits

- Achievement, mob and zone data from [Bonzz's Slayer page](https://www.bonzz.com/slayerach.htm), [Allakhazam](https://everquest.allakhazam.com/) comments, and EverQuest Nexus.
- Hunting inspired by MultiHunter by Nerp (priority system by knave23). Slayer Farm's hunter is a separate rewrite.

## License

MIT. See [LICENSE](LICENSE).
