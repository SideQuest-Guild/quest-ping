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

A bouncing arrow sits over the nameplate of the mob the next press will ping.

## Mobs it finds

QuestPing reads your quest log and hunts every kill objective you have not finished, such as "3/10 Skullsplitter Mystic slain". New quests count as soon as you take them.

A mob counts as near when its enemy nameplate shows, which the game does up to 45 yards away. QuestPing skips mobs that are dead, friendly, tapped by another player or already in a fight.

## Integrations

- Polestar: if you use Polestar, QuestPing reads its quest database. That adds the mobs that drop quest items, such as "2/6 Troll Tusk", and the mobs that count toward a kill line with a group name, such as "Gnolls slain". You can turn this off in the settings.
- Minimap: QuestPing shows in the game's minimap addon list and has its own minimap button. The button uses LibDBIcon, so minimap button collectors pick it up.
- Questie: support is planned.

## Hunt window

Open the hunt window with `/questping`, its key binding or the minimap button. The left side lists the quests you are hunting and how many of their mobs are near. The right side shows the chosen quest: its progress, each objective, the mobs that count for it and how many of them are near.

## Settings

The settings are in Options > AddOns > QuestPing. You can:

- turn party chat on or off
- pick the raid icon
- turn the arrow on or off
- turn the Polestar database on or off
- turn enemy nameplates on or off
- show or hide the minimap button

## Setup

1. Bind "Ping the next quest mob" in Options > Key Bindings > AddOns > QuestPing.
2. Turn on enemy nameplates if they are off.

To keep the button on an action bar, make a macro with `/click QuestPingButton`.

## Limits

- The game does not let addons change the button during combat. In a fight, presses work through the mobs that were near when the fight started. New mobs join when it ends.
- The button acts when you release the key, so each press counts once.
- QuestPing cannot point an arrow across the world. The game tells addons where a mob's nameplate is on screen, not where the mob stands.
