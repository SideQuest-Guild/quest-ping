# Changelog

## v0.2.1 (2026-11-13)

### Fixed

- A press finds and the button comes up for mobs of Forever's own quests, whose spawns come from Polestar's Codex by name when no quest database knows them

## v0.2.0 (2026-11-13)

### New

- A guide arrow points at the nearest place a mob you still need spawns, and Questie's quest database works like Polestar's
- The ping button looks like Polestar's, shows its key, and can stay on screen always or hide for key-only use
- /questping status shows your key, what the last press ran and whether the game's pings are on, and a refused ping is explained in chat
- A press targets the next quest mob first, like Polestar's target button, and the next press marks and pings it only if it's free, so a tapped or busy mob is never pinged
- In a fight, a press pings another quest mob and puts you back on yours, the button says what the next press does, and /questping status shows its macro

### Fixed

- The guide arrow turns smoothly and skips spawns you've emptied, and free quest mobs get a quest icon on their nameplate
- A press targets the mob and pings your target, since the game makes no ping for a nameplate, and a Range setting limits how far a mob may be
- A press targets by name and marks the mob, mobs your party still need stay hunted, a drag never errors in combat, and the game's own ping line replaces QuestPing's chat call-out
- A press finds quest mobs too far for a nameplate by name, the bouncing arrow sits only on the mob you pressed for, and the spawn guide arrow is off unless you turn it on
- Like Polestar's target button, the ping button is up whenever a mob you need spawns nearby, and a tapped mob in view no longer hides a free one farther out
- A press tries every quest mob you need, nearest spawn first, like Polestar's target button, instead of only those spawning within 200 yards
- Far quest mobs you're done with are still looked for while someone in your group is on the quest, and pinged once their tooltip shows someone short
- The ping key works while no quest mob is in view: the button goes invisible instead of hidden, since the game drops a key's release on a hidden button
- A press passes over quest mobs below full health for a free one, and never marks or pings a hurt one

## v0.1.0 (2026-11-13)

### New

- QuestPing pings the quest mobs you still need when they're near, calls them out in party chat, and shows them in a hunt window

