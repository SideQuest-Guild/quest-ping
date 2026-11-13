# QuestPing

QuestPing is a World of Warcraft: Forever addon for quest hunting. When a mob you still need is near, a button appears. Press its key and QuestPing pings the mob for your group, names it in party chat and targets it.

It replaces this macro, which you would otherwise edit for every quest:

```
/cleartarget [dead]
/targetexact Skullsplitter Mystic
/ping [@target,exists,nodead] Attack
```

## Each press

- Pings the next mob you have not pinged yet with the Attack ping. Your target stays on the mob you are fighting.
- Says "Skullsplitter Mystic here" in party chat, with a raid icon in front. In a raid it uses raid chat. Alone, it says nothing.
- Targets a quest mob if you have no live target.
- Pings and names each mob once, so you can press the key as often as you like.

A bouncing arrow sits over the nameplate of the mob the next press will ping. A quest icon sits beside every mob you need that nobody has: not tapped by another player and not in a fight.

## Guide arrow

When no mob you still need is in view, an arrow near the top of the screen points at the nearest place one spawns, with its name and distance. Walk where it points. Once a needed mob's nameplate comes up, the bouncing arrow over it takes over. If you reach a spawn and none of its mobs are alive, the arrow skips that spawn for 5 minutes and points at the next one. The guide arrow needs Polestar or Questie, since their quest databases know where mobs spawn. It hides in instances.

## Mobs it finds

QuestPing reads your quest log and hunts every kill objective you have not finished, such as "3/10 Skullsplitter Mystic slain". New quests count as soon as you take them.

A mob counts as near when its enemy nameplate shows, which the game does up to 45 yards away. QuestPing skips mobs that are dead, friendly, tapped by another player or already in a fight.

## Integrations

- Polestar: if you use Polestar, QuestPing reads its quest database. That adds the mobs that drop quest items, such as "2/6 Troll Tusk", and the mobs that count toward a kill line with a group name, such as "Gnolls slain". It also gives the guide arrow its spawn places.
- Questie: if you use Questie, QuestPing reads its database the same way. With both installed, Polestar is asked first.
- Minimap: QuestPing shows in the game's minimap addon list and has its own minimap button. The button uses LibDBIcon, so minimap button collectors pick it up.

## Hunt window

Open the hunt window with `/questping`, its key binding or the minimap button. The left side lists the quests you are hunting and how many of their mobs are near. The right side shows the chosen quest: its progress, each objective, the mobs that count for it and how many of them are near.

## Settings

The settings are in Options > AddOns > QuestPing. You can:

- turn party chat on or off
- pick the raid icon
- turn the nameplate arrow on or off
- turn the quest icons on or off
- turn the guide arrow on or off
- turn the quest databases on or off
- turn enemy nameplates on or off
- show or hide the minimap button
- show the ping button when a quest mob is near, always, or never

## Setup

1. Click the ping button when it appears, or bind "Ping the next quest mob" in Options > AddOns > QuestPing. The button shows its key in the corner and the next mob's name beside it. Shift-drag moves it.
2. Turn on enemy nameplates if they are off.

To keep the button on an action bar, make a macro with `/click QuestPingButton`.

## Limits

- The game does not let addons change the button during combat. In a fight, presses work through the mobs that were near when the fight started. New mobs join when it ends.
- The button acts when you release the key, so each press counts once.
- The guide arrow points at spawn places from the quest database, not at a live mob. The game tells addons where a mob is only once its nameplate is on screen.
