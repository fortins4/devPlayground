# Traversal / map scale

Overland region graph for Leinster → Ireland. Design: [`docs/MAP_SCALE.md`](../../docs/MAP_SCALE.md).

| Piece | Role |
|---|---|
| [`travel_distances.gd`](travel_distances.gd) (`class_name TravelDistances`) | Region ids, horse/foot day matrix, shortest path |
| `Game.current_region` | Live region id (seeds `&"leinster"`) |

No scene loads here — callers advance `WorldClock` and swap regions themselves.

Church sanctuary sites that hang off these region ids: [`systems/sanctuary/`](../sanctuary/) (`glendalough` → `wicklow_glendalough`, `clonmacnoise` → `clonmacnoise`).

## API

```gdscript
TravelDistances.horse_days(&"leinster", &"dublin")     # 2
TravelDistances.foot_days(&"leinster", &"dublin")      # 4
TravelDistances.list_connections(&"leinster")          # neighbour rows
TravelDistances.shortest_horse_path(&"leinster", &"connacht")
print(TravelDistances.get_debug_text())
```

Days are **calendar days** on the living clock when the player commits a travel
gate. Local greybox meters are separate (see MAP_SCALE).

## Slice stance

- Only `leinster` is an authored roam region in the vertical slice.
- Other ids exist so UI / timeline / rumors can talk about destinations and so
  event spacing (Bannow → ports → marriage → Dublin) stays honest against travel cost.

## Remote probe

```gdscript
print(TravelDistances.to_debug_dict())
print(TravelDistances.list_connections(&"dublin", &"foot"))
```
