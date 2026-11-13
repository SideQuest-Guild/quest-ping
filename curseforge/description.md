# QuestPing

QuestPing is a World of Warcraft: Forever addon for quest hunting. When a mob you still need is near, a button appears. Press its key and QuestPing targets the mob, marks it with a raid icon and pings it for your group.

It replaces this macro, which you would otherwise edit for every quest:

```
/cleartarget [dead]
/targetexact Skullsplitter Mystic
/ping [@target,exists,nodead] Attack
```

## Each press

Like Polestar's target button, a press targets first. The ping comes on the next press, once QuestPing can see what you've got.

- If you have no quest mob targeted, or you're done with yours, a press targets the next one by name, like Polestar's target button. It tries the free ones in view first, then every other mob you need, nearest known spawn first. This reaches any mob the game has loaded around you, well past the 45-yard nameplates and even behind trees, but the game tells addons nothing about a mob until it's your target. A tapped or hurt mob in view doesn't hide a free one farther out: the next press goes on to the next mob of that name, then to the other names. If it finds none, you keep the quest mob you had.
- If your target is a quest mob that's free (not tapped, not in a fight, not hurt, and not pinged in the last 10 minutes), a press marks it with a raid icon and pings it with the Attack ping. A tapped, busy or hurt mob is never marked or pinged, even a far one. The next press just moves on.
- The game puts the ping in your group's chat ("Attack: Venture Co. Geologist"), so QuestPing adds no chat line of its own.
- Raid icons go on in order: the skull first, then the cross, then the square and so on for each other mob. QuestPing skips icons already in use and never takes an icon off a mob. In a raid, only the leader and assistants can mark.
- Targeting goes by name, since the game ignores nameplates for targeting. When several mobs share a name, the game picks which one you get.
- The Range setting limits how far away a mob may be, from 8 to 48 yards. By default it takes any mob whose nameplate shows. With a Range set, far mobs are out of it.

A bouncing arrow sits over the nameplate of the mob you pinged, while it's your target. A quest icon sits beside every mob you need that nobody has: not tapped by another player, not in a fight and not hurt.

## Spawn guide arrow

This one is off unless you turn it on, since it can only guess. When no mob you still need is in view, an arrow near the top of the screen points at the nearest place one spawns, with its name and distance. If you reach a spawn and none of its mobs are alive, the arrow skips that spawn for 5 minutes and points at the next one. It needs Polestar or Questie, since their quest databases know where mobs spawn, and a spawn may be empty. It hides in instances.

## Mobs it finds

QuestPing reads your quest log and hunts every kill objective you have not finished, such as "3/10 Skullsplitter Mystic slain". New quests count as soon as you take them.

It also hunts for your party. If you have finished an objective but someone in your group still needs it, QuestPing keeps hunting those mobs, far ones included. It reads the game's own tooltip on each mob, which lists every party member on the quest with their count, so nobody else needs the addon. Party members who run QuestPing or Polestar also share their progress for the hunt window.

A mob counts as near when its enemy nameplate shows, which the game does up to 45 yards away. QuestPing skips mobs that are dead, friendly or tapped by another player. A mob already in a fight or below full health is never pinged, and a press passes it over: targeting by name can still land on one, and then the next press moves on.

## Integrations

- Polestar: if you use Polestar, QuestPing reads its quest database. That adds the mobs that drop quest items, such as "2/6 Troll Tusk", and the mobs that count toward a kill line with a group name, such as "Gnolls slain". It also gives the spawn guide arrow its spawn places.
- Questie: if you use Questie, QuestPing reads its database the same way. With both installed, Polestar is asked first.
- Minimap: QuestPing shows in the game's minimap addon list and has its own minimap button. The button uses LibDBIcon, so minimap button collectors pick it up.

## Hunt window

Open the hunt window with `/questping`, its key binding or the minimap button. The left side lists the quests you are hunting and how many of their mobs are near. The right side shows the chosen quest: its progress, each objective, the mobs that count for it and how many of them are near.

## Settings

The settings are in Options > AddOns > QuestPing. You can:

- pick the raid icon for marking, or none
- turn the nameplate arrow on or off
- turn the quest icons on or off
- turn the spawn guide arrow on or off
- turn the quest databases on or off
- set how far away a mob may be
- turn enemy nameplates on or off
- show or hide the minimap button
- show the ping button when a quest mob is near, always, or never

## Setup

1. Click the ping button, or bind "Target, then ping, the next quest mob" in Options > AddOns > QuestPing. The button shows up, dimmed, as soon as a mob you need spawns within 300 yards, and lights up once one is in view. It shows its key in the corner and the next mob's name beside it. Shift-drag moves it.
2. Turn on enemy nameplates if they are off.

To keep the button on an action bar, make a macro with `/click QuestPingButton`.

## Limits

- Addons can't ping on their own. The game only targets and pings from a key press or a click.
- In a fight on a live mob, a press pings another quest mob and puts you straight back on yours (through your focus, which it clears after). The game freezes the button for the whole fight, so these are written at the pull and pinged blind: a tapped mob can get one, and if nothing is found the ping lands on your own mob. The quick target switch may clip an auto-attack swing or a cast.
- The button acts when you release the key, so each press counts once.
- The game tells addons about an enemy only through its nameplate or your target. So no arrow can point at a far mob, and the spawn guide arrow points at spawn places from the quest database, not at a live mob.
