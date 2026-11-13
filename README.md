# QuestPing

A World of Warcraft: Forever addon. When mobs you still need for a quest are near, a button shows up. Spam its
key: each press targets the next one, marks it with a raid icon and pings it **Attack** for your group, once per
mob.

It replaces a macro like this, without editing it for every quest:

```
/cleartarget [dead]
/targetexact Skullsplitter Mystic
/ping [@target,exists,nodead] Attack
```

## What a press does

- **Targets the next mob not pinged yet and pings it** with the Attack ping. The game puts the ping in your
  group's chat ("Attack: Venture Co. Geologist"), so QuestPing adds no chat line of its own. Each mob is pinged
  once; it can be pinged again after 10 minutes. On Forever, `/target`
  and `/ping` do nothing with a nameplate, so a press targets by name (`/targetexact`, like the old macro) and
  pings your target. By name, the game picks which of several same-named mobs you get (the nearest, then the
  next on later presses), so with a pack of one kind a press can land on one already pinged or in a fight.
- **Marks it** with a raid icon: skull first (or the icon you pick), then cross, square and on down for each
  other mob, skipping icons already on someone in view. A mob that already wears an icon keeps it. In a raid
  only the leader and assistants can mark.
- Once every mob in view is pinged, presses only target, so spamming is safe.
- **Far mobs:** with no quest mob targeted, a press also looks for the ones too far for a nameplate (you can see
  their names past 45 yards, but the game gives addons nothing about them). It drops your target and tries each
  far name in turn with `/targetexact`, then pings what it found, unmarked: QuestPing can't tell a far mob is
  tapped or in a fight until it's targeted. The ping button stays hidden for far mobs; the key works anyway.
- **Range** in the settings limits how far away a mob may be (8 to 48 yards, or any nameplate, the default).
  With a Range set, far mobs are out of it.
- A **bouncing arrow** sits over the nameplate of the mob a press marked, while it's your target, and a
  **quest icon** sits beside every needed mob nobody has (not tapped, not in a fight).

## Spawn guide arrow

Off unless you turn it on in the settings, since it can only guess. When no mob you still need is in view, an
arrow near the top of the screen points at the nearest place one spawns, with its name and distance. The spawn
places come from Polestar's or Questie's quest database, so it needs one of them, and a spawn may be empty. A
spawn you reach with none of its mobs alive in view is skipped for 5 minutes while it respawns. It hides in
instances. Shift-drag moves it.

## Which mobs

- **Wanted:** every kill objective in your quest log that isn't finished ("3/10 Skullsplitter Mystic slain").
  With Polestar or Questie installed, its quest database adds the mobs that drop quest items ("2/6 Troll Tusk")
  and the mobs a kill line counts under a group name ("Gnolls slain"). Polestar is asked first.
- **For your party:** a mob stays wanted while someone in your group still needs it, even after you're done.
  The game's own tooltip on a mob lists every party member on its quest with their count ("Aewie Booty 5/8
  Tumbled Crystal"), and QuestPing reads that, so it works with no addon on their side and covers drop items
  too. QuestPing users in the group also share what they still need in hidden addon messages (party or raid
  only), and Polestar's party sync counts when it's on; those show in the hunt window ("For Ana"). "Hunt for
  your party too" in the settings turns all of this off.
- **Near:** the mob has an enemy nameplate up, which the game shows out to 45 yards. Enemy nameplates are off by
  default; `/questping plates` turns them on.
- **Never:** dead, friendly, or tapped by someone else (the grey ones).
- **Not pinged or called out:** mobs already fighting you or anyone else. You can still target them.

## Use

- **Click the ping button** or bind a key (Options > AddOns > QuestPing has the key rows too). The button shows
  its key in the corner and the next mob's name beside it. Shift-drag moves it.
- The **Ping button** setting picks when the button is on screen: when a quest mob is near (default), always
  (dimmed while nothing is near, so you can find and place it), or never (key binding only).
- To keep your own macro button, make its text `/click QuestPingButton`.
- The button acts when you let go of the key, not when you press it, so each press counts once.

## Window and settings

- **The hunt window** (`/questping`, its own key binding, or right-click the ping button) is laid out like
  Attune's: the quests you're hunting on the left with how many of their mobs are near, and the picked quest on
  the right with a progress bar, each objective, which mobs count for it and how many are near.
- **Settings** are under **Options > AddOns > QuestPing** (or the window's Settings button, or
  `/questping options`): which raid icon a press marks with (or none), the nameplate arrow, the quest
  icons, the spawn guide arrow, the range, using quest databases, enemy nameplates, the ping button, the minimap
  button, and putting things back where they start.
- `/questping status` prints what you're hunting and what's near in chat.

## In combat

The game only lets an addon rewrite the button out of combat, and a press never pulls you off a live target in a
fight. So in a fight a press pings only while you have no live target; the mobs it skips get their pings when the
fight ends.

## What no addon can do

- **Ping on its own.** Targeting and pinging are protected: the game runs them only from a key press or a click.
- **See mobs past nameplate range.** The game tells addons about an enemy only through its nameplate (45 yards
  at most) or your target, so QuestPing can't know a far mob's spot, health or tap, and no arrow can point at
  one.

## Install

Copy `QuestPing/` into `_forever_/Interface/AddOns/`.

## Develop

```sh
luajit tests/run_tests.lua
luacheck QuestPing tests
```
