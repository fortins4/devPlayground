# Ríocht: Where Things Stand

## Read first
Read **[GET_UP_TO_SPEED.md](GET_UP_TO_SPEED.md)** before any task. It has the locked rules, and they win over anything here.

## What's on main
Tip: `527008a` (2026-10-13 22:15 ET), "Trough takes three bucket trips".

The opening (`scenes/prologue/opening_cattle_drive.tscn`, F4 from the main greybox) is a set sequence with Máire as the hub:

1. **Máire at the door.** Máire is Cian's mother. She waves and talks on her own when Cian comes near. After each task he goes back to her for the next one.
2. **Bucket to the trough.** Pick up the stave bucket by the byre, fill it at the dug-out spring scoop west of the house, and pour it at the trough. It takes three trips, and each pour raises the water by a third (HUD shows "Trough n/3"). Cian stows the goad and carries the bucket by the handle with both hands. The load slows him to a braced walk and blocks sprint. The goad is drawn again after the last pour.
3. **Herd drive.** No cow is tethered at the start; all six go. One of the 6 cows is bogged at the pasture. Free her, drive her back to the herd, then drive all 6 home. A stray dog ambushes and scatters them on the lane.
4. **Penning.** All 6/6 in the night pen, then close and latch the pen gate to end the drive.
5. **Milk cow.** Cian ropes the red milk cow at the latched gate (lifts the latch, swings the west leaf, she steps out, he shuts and re-latches it so the other five stay in), leads her on the rope to the post by the house and ties her there by hand (goad stowed, both hands) for the morning milking.
6. **Stow and meal.** Stow the goad, eat at the house: Cian sits at the stool, then gets up cleanly back into walking.

### Ringfort and history pass (H1–H8)
1. A family **ráth** around the farmstead, with the night pen and latch inside the entrance.
2. A round wattle-and-daub **roundhouse** under a thatch cone.
3. Low turfed **earth banks** with ditches, **wattle** fence runs, open grazing.
4. A dark **woodland** edge: oak, ash, alder, hazel, with holly and hawthorn underneath.
5. Small dark native **cattle** (Kerry/Dexter type), short-horned or polled, with no floating labels.
6. Small oat and barley **plots** outside the ráth, and a rotary **quern** by the meal spot.
7. The bogs are now small **fen** hollows, with a walkable plank **tóchar** (trackway) across the far one.
8. The boreen is now a worn **mud track**, and a **carved post and cairn** replace the written signs.

### Combat basics
1. The goad swings in three directions (top, left, right), aimed with the mouse look-guard.
2. Hold to charge, release to swing. The bottom attack is a chargeable **stab**.
3. Cian can walk while attacking. Sprint blocks attacks.
4. **No stamina** at all: no meter, no drain, no gates.

## Known open rough edges
None of these has a fix on main yet:
1. The bog shaft spikes for one frame.
2. T (restart) resets the herd and Cian but not the bucket chore.
3. The trough's 1/3 and 2/3 water levels look alike.
4. The hint shows twice at the trough (the world "Trough" label plus the HUD hint).
5. The cows have tube legs and a stiff trot.
6. The cows' heads hang low.
7. Penned cows overlap each other.
8. The goad can miss at the tip of a cow's rump.

## In progress (local, not on main)
1. **Realism audit** by the Godot bot.
2. **Next-story-beat plan** by the Systems bot.
3. **Opening crops** being changed to young green May growth (Godot, local).

## How we work
1. Every option or rough-edge list is numbered, and the user picks by number.
2. Build only what's picked. No extra scenes, areas or features.
3. Work stays local until the user gives an A in Lead's chat.
4. Lead fast-forwards main. No force-pushes.
5. Stills (including mid-arc stills for combat) are checked before any A/B goes to the user.
