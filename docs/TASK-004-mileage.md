# Task 004 — mileage tracking

Scope: count the distance driven and keep it in the save file. No money, rewards or vehicle wear yet.

## How it counts

- Mileage only counts while the HUD is READY, i.e. while Earth reports a valid vehicle position. (Originally this also required arriving at the base or saved location first; that check has since been removed so Save works anywhere straight away.)
- Each frame, the geographic (haversine) distance between the previous and current vehicle reading is added to `progression.totalDistanceKm`.
- A step faster than 150 m/s (540 km/h) is treated as a teleport: it is not counted, and counting continues from the new position.
- A frame with zero elapsed time is not counted.
- When the vehicle position is unavailable (no vehicle, Earth not running), the odometer is cleared; movement during the gap is not counted.

## Saving

- Mileage is saved only by the manual **Save** button, together with the position, using the existing two-slot save files. The save schema is unchanged (`totalDistanceKm` was already reserved).
- The HUD shows the total and, when non-zero, how much has been driven since the last Save ("unsaved").
- Exiting the game or **Reload Enduro** without saving discards unsaved mileage and restores the last saved total.

## Known limits

- Distance is measured as straight lines between frames on a sphere. Over normal frame rates this matches the driven path closely; it ignores elevation change.
- Very slow GPS-style jitter of a parked vehicle could add tiny amounts; physics positions are normally stable when parked.
- The 150 m/s limit means unusually fast vehicles above 540 km/h would not accumulate mileage.
- Not yet tested in the real game.
