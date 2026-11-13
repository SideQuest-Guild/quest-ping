# QuestPing

QuestPing is a World of Warcraft: Forever addon for quest hunting. When a mob you still need is near, a button appears. Press its key and QuestPing targets the mob, marks it with a raid icon and pings it for your group.

It replaces this macro, which you would otherwise edit for every quest:

```
/cleartarget [dead]
/targetexact Skullsplitter Mystic
/ping [@target,exists,nodead] Attack
```

## Each press

- Targets the next mob you have not pinged yet, by name, and pings it with the Attack ping. The game only makes a ping on your target, so the press has to target the mob. When several mobs share a name, the game picks which one you get.
- The game puts the ping in your group's chat ("Attack: Venture Co. Geologist"), so QuestPing adds no chat line of its own.
- Marks the mob with a raid icon: the skull first, then the cross, then the square and so on for each other mob. It skips icons already in use and never takes an icon off a mob. In a raid, only the leader and assistants can mark.
- Pings each mob once, so you can press the key as often as you like. Once every mob is pinged, a press only targets.
- The Range setting limits how far away a mob may be, from 8 to 48 yards. By default it takes any mob whose nameplate shows.

A bouncing arrow sits over the nameplate of the mob the next press will ping. A quest icon sits beside every mob you need that nobody has: not tapped by another player and not in a fight.

## Guide arrow

When no mob you still need is in view, an arrow near the top of the screen points at the nearest place one spawns, with its name and distance. Walk where it points. Once a needed mob's nameplate comes up, the bouncing arrow over it takes over. If you reach a spawn and none of its mobs are alive, the arrow skips that spawn for 5 minutes and points at the next one. The guide arrow needs Polestar or Questie, since their quest databases know where mobs spawn. It hides in instances.

## Mobs it finds

QuestPing reads your quest log and hunts every kill objective you have not finished, such as "3/10 Skullsplitter Mystic slain". New quests count as soon as you take them.

It also hunts for your party. If you have finished an objective but someone in your group still needs it, QuestPing keeps hunting those mobs. It reads the game's own tooltip on each mob, which lists every party member on the quest with their count, so nobody else needs the addon. Party members who run QuestPing or Polestar also share their progress for the hunt window.

A mob counts as near when its enemy nameplate shows, which the game does up to 45 yards away. QuestPing skips mobs that are dead, friendly, tapped by another player or already in a fight.

## Integrations

- Polestar: if you use Polestar, QuestPing reads its quest database. That adds the mobs that drop quest items, such as "2/6 Troll Tusk", and the mobs that count toward a kill line with a group name, such as "Gnolls slain". It also gives the guide arrow its spawn places.
- Questie: if you use Questie, QuestPing reads its database the same way. With both installed, Polestar is asked first.
- Minimap: QuestPing shows in the game's minimap addon list and has its own minimap button. The button uses LibDBIcon, so minimap button collectors pick it up.

## Hunt window

Open the hunt window with `/questping`, its key binding or the minimap button. The left side lists the quests you are hunting and how many of their mobs are near. The right side shows the chosen quest: its progress, each objective, the mobs that count for it and how many of them are near.

## Settings

The settings are in Options > AddOns > QuestPing. You can:

- pick the raid icon for marking, or none
- turn the nameplate arrow on or off
- turn the quest icons on or off
- turn the guide arrow on or off
- turn the quest databases on or off
- set how far away a mob may be
- turn enemy nameplates on or off
- show or hide the minimap button
- show the ping button when a quest mob is near, always, or never

## Setup

1. Click the ping button when it appears, or bind "Ping the next quest mob" in Options > AddOns > QuestPing. The button shows its key in the corner and the next mob's name beside it. Shift-drag moves it.
2. Turn on enemy nameplates if they are off.

To keep the button on an action bar, make a macro with `/click QuestPingButton`.

## Limits

- The game does not let addons change the button during combat, and a press never pulls you off a live target. In a fight, a press pings only while you have no live target. The mobs it skips get their pings when the fight ends.
- The button acts when you release the key, so each press counts once.
- The guide arrow points at spawn places from the quest database, not at a live mob. The game tells addons where a mob is only once its nameplate is on screen.
