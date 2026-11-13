# QuestPing

A World of Warcraft: Forever addon. When mobs you still need for a quest are near, a button shows up. Spam its
key: each press pings the next one **Attack** for your group and says it in party chat, once per mob, and targets
one for you.

It replaces a macro like this, without editing it for every quest:

```
/cleartarget [dead]
/targetexact Skullsplitter Mystic
/ping [@target,exists,nodead] Attack
```

## What a press does

- **Pings the next mob not pinged yet**, without pulling your target off it, and says "Skullsplitter Mystic here"
  in party chat with a raid icon in front (skull unless you pick another; raid chat in a raid; nothing when you're
  alone). Each mob is pinged and called out once; it can be pinged again after 10 minutes.
- **Targets** the first quest mob in view if you have no live target, or if you're targeting something that isn't
  one. In a fight it never pulls you off a live target.
- Once every mob in view is pinged, presses only target, so spamming is safe.
- A **bouncing arrow** sits over the nameplate of the mob the next press will ping.

## Guide arrow

When no mob you still need is in view, an arrow near the top of the screen points at the nearest place one
spawns, with its name and distance. Walk where it points; once a needed mob's nameplate comes up, the bouncing
arrow over it takes over. The spawn places come from Polestar's or Questie's quest database, so the guide arrow
needs one of them. It hides in instances. Shift-drag moves it.

## Which mobs

- **Wanted:** every kill objective in your quest log that isn't finished ("3/10 Skullsplitter Mystic slain").
  With Polestar or Questie installed, its quest database adds the mobs that drop quest items ("2/6 Troll Tusk")
  and the mobs a kill line counts under a group name ("Gnolls slain"). Polestar is asked first.
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
  `/questping options`): party chat on or off, which raid icon goes in front, the nameplate arrow, the guide
  arrow, using quest databases, enemy nameplates, the minimap button, and putting things back where they start.
- `/questping status` prints what you're hunting and what's near in chat.

## In combat

The game only lets an addon rewrite the button out of combat. In a fight, presses still move through the pings
that were lined up when the fight started, and everything catches up when it ends. So a mob that comes into view
mid-fight waits until the fight is over, and one someone pulls mid-fight can still get its ping, though it isn't
called out in chat.

## Install

Copy `QuestPing/` into `_forever_/Interface/AddOns/`.

## Develop

```sh
luajit tests/run_tests.lua
luacheck QuestPing tests
```
