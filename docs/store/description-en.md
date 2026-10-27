# RotationCore

Rotation helper for World of Warcraft 3.3.5a (WotLK).

RotationCore watches your spec, talents, resources and target, then highlights
the next ability to press. It works out of the box and needs no setup.

**10 classes · 29 specs · 12 languages**

## What it does

The addon follows your current build and the state of the fight, then shows the
next ability in a priority list. It does not cast anything: every button is
pressed by the player.

Works on any private server running the 3.3.5a client, including Warmane,
Project Epoch and other WotLK realms.

## Highlights

- Action-bar highlight with priority colours and glow styles.
- Icon window with the top recommendations, keybinds and target mode.
- Live DPS forecast with actual DPS and loss percentage.
- Cooldown and interrupt windows.
- Boss timeline with or without DBM and BigWigs.
- Mentor, exam, training and PvP modes.
- Healer assist and DPS support for heal specs.
- Custom rotation through a plain-text priority list.
- Boss profiles and per-spec profiles.
- 12 languages: English, Russian, German, French, Spanish, Italian, Portuguese,
  Korean, Chinese (Simplified and Traditional).
- Setup wizard, tooltips for every option and several UI themes.

## Supported classes and specs

| Class | Specs |
|---|---|
| Death Knight | Blood · Frost · Unholy |
| Druid | Balance · Feral (Cat) · Feral (Bear) |
| Hunter | Beast Mastery · Marksmanship · Survival |
| Mage | Arcane · Fire · Frost |
| Paladin | Retribution · Protection · Holy |
| Priest | Shadow · Discipline · Holy |
| Rogue | Assassination · Combat · Subtlety |
| Shaman | Elemental · Enhancement |
| Warlock | Affliction · Demonology · Destruction |
| Warrior | Arms · Fury · Protection |

## Installation

1. Download `RotationCore-1.0.4.zip` from the releases page.
2. Extract it into `World of Warcraft/Interface/AddOns/` so the folders land as
   `AddOns/RotationCore` and `AddOns/RotationCore_<Class>`.
3. Enable **Load out of date AddOns** in the addon list.
4. Type `/rc` in game to open the options window, or `/rc wizard` for guided
   setup.

## Slash commands

| Command | Action |
|---|---|
| `/rc` | Open options |
| `/rc wizard` | Setup wizard |
| `/rc toggle` | Enable or disable the addon |
| `/rc spec <name>` | Pick a build |
| `/rc pause` | Freeze recommendations |
| `/rc train`, `/rc pvp`, `/rc exam`, `/rc mentor` | Mode toggles |
| `/rc apl` | Custom rotation |
| `/rc boss` | Boss profiles |
| `/rc hub` | Coach hub |
| `/rc selfcheck` | Self-test |

## FAQ

**Does it play the game for me?**
No. It only highlights the next ability, and you press every button yourself.

**Will it work without DBM or BigWigs?**
Yes. The boss timeline works on its own. DBM and BigWigs add precise timers.

**Is my data safe?**
Yes. Settings are stored locally by the game and never leave the client.

**Does it work on private servers?**
It targets the standard 3.3.5a game data and works on private servers running
3.3.5a. Custom abilities can be added with your own rotation through `/rc apl`.

## Links

- Source: https://github.com/Hijackery/RotationCore
- Releases: https://github.com/Hijackery/RotationCore/releases
- Issues: https://github.com/Hijackery/RotationCore/issues
- Developer guide: https://github.com/Hijackery/RotationCore/blob/main/docs/DEVELOPMENT.md

## License

MIT. See https://github.com/Hijackery/RotationCore/blob/main/LICENSE.
