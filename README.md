# VehicleSpawnArea

A multi-location, server-authoritative vehicle spawner for FiveM. Supports standalone use and auto-detects **ESX**, **QBCore**, and **QBox** frameworks. Features layered ACE and job-based permissions, configurable parking bays, and an ox_lib-powered menu system.

---

## Features

- **Multi-location** — Define as many garages as you need, each with their own vehicles, bays, and permissions
- **Framework auto-detection** — Detects QBox → QBCore → ESX → Standalone with no manual configuration
- **Layered permissions** — Location-level gates combined with optional per-vehicle overrides
- **ACE & job permissions** — Use either or both; supports `'none'`, `'ace'`, `'job'`, and `'both'` modes
- **Server-authoritative** — All spawn requests are validated server-side before the vehicle is created
- **Anti-spam cooldown** — Configurable cooldown between spawn requests per player
- **Dynamic bay states** — Bay markers change colour (green/red) to reflect occupancy in real time
- **Auto vehicle replacement** — Optionally delete the previous vehicle in a bay before spawning a new one
- **Dependency-light** — Only requires [ox_lib](https://github.com/overextended/ox_lib)

---

## Dependencies

| Dependency | Required |
|---|---|
| [ox_lib](https://github.com/overextended/ox_lib) | ✅ Yes |
| ESX / QBCore / QBox | ❌ Optional (standalone supported) |

---

## Installation

1. Drop the `VehicleSpawnArea` folder into your FiveM server's `resources` directory.
2. Add `ensure VehicleSpawnArea` to your `server.cfg`.
3. Configure your locations, vehicles, and permissions in [`shared/config.lua`](shared/config.lua).
4. If using ACE permissions, add the relevant ace entries to your `server.cfg` (see [Permissions](#permissions)).
5. Restart the resource or server.

---

## File Structure

```
VehicleSpawnArea/
├── fxmanifest.lua          — Resource manifest
├── shared/
│   ├── config.lua          — All user-facing configuration (edit this)
│   └── framework.lua       — Framework auto-detection (do not edit)
├── client/
│   └── main.lua            — Client-side logic (zones, menus, spawning)
└── server/
    └── main.lua            — Server-side logic (permissions, anti-spam)
```

---

## Configuration

All configuration lives in [`shared/config.lua`](shared/config.lua).

### Global Settings

```lua
Config.PermissionMode       = 'both'    -- 'none' | 'ace' | 'job' | 'both'
Config.SpawnCooldown        = 5         -- Seconds between spawns per player
Config.OccupiedCheckRadius  = 3.0       -- Radius (metres) to detect an occupied bay
Config.DeletePreviousVehicle = true     -- Replace existing vehicle in bay on spawn
Config.Debug                = false     -- Print permission checks to server console
```

### Adding a Location

Each location is a self-contained garage entry inside `Config.Locations`:

```lua
Config.Locations = {
    ['my_garage'] = {
        label    = 'My Garage',

        -- Location-level permissions
        ace      = 'vehiclespawn.mygarage',  -- nil = no ACE check
        jobs     = { 'mechanic' },           -- nil = no job check
        minGrade = 0,                        -- Minimum job grade

        -- Central menu interaction point (player presses E here)
        menuPoint = {
            coords = vector3(0.0, 0.0, 0.0),
            radius = 3.0,
            marker = {
                type         = 20,
                scale        = 1.5,
                color        = { r = 0, g = 200, b = 255 },
                drawDistance = 15.0,
            },
        },

        -- Parking bays
        bays = {
            {
                id      = 1,
                label   = 'Bay 1',
                coords  = vector3(0.0, 0.0, 0.0),
                heading = 0.0,
                marker  = {
                    type  = 36,
                    scale = 1.5,
                    color = { r = 0, g = 255, b = 0 },
                },
            },
        },

        -- Vehicles available at this location
        vehicles = {
            {
                label = 'Sultan RS',
                model = 'sultanrs',
                -- Optional per-vehicle permission overrides
                -- ace      = 'vehiclespawn.mygarage.sultan',
                -- jobs     = { 'mechanic' },
                -- minGrade = 2,
            },
        },
    },
}
```

### Layered Permission Logic

Permissions work in two layers:

1. **Location-level** — The player must pass this to see or interact with the garage at all.
2. **Vehicle-level** — If a vehicle has its own `ace`/`jobs` fields, those are checked *on top of* the location check. If a vehicle has no permissions defined, the location check is sufficient.

When `Config.PermissionMode = 'both'`, a player must pass **ACE *or* job** (not both). This is the most common and permissive setup.

---

## Permissions

### ACE Permissions

Add these lines to your `server.cfg`, adapting the group names to your setup:

```cfg
# Grant a group access to a location
add_ace group.police     vehiclespawn.police     allow
add_ace group.ambulance  vehiclespawn.ambulance  allow

# Grant a group access to a specific vehicle within a location
add_ace group.police     vehiclespawn.police.k9  allow
```

Assign players to groups as normal:

```cfg
add_principal identifier.steam:110000100000001 group.police
```

### Job Permissions (ESX / QBCore / QBox)

Set `jobs` in the location or vehicle config. The player's job name and grade are fetched from the active framework automatically. No extra server.cfg entries are needed.

```lua
jobs     = { 'police', 'sheriff' },
minGrade = 2,  -- Grade 2 or above only
```

---

## Framework Support

The resource auto-detects the active framework on startup, checking in this order:

| Priority | Framework | Resource Checked |
|---|---|---|
| 1 | QBox | `qbx_core` |
| 2 | QBCore | `qb-core` |
| 3 | ESX | `es_extended` |
| 4 | Standalone | Fallback |

In standalone mode, job checks are automatically skipped. Only ACE permissions apply.

---

## Spawn Flow

```
Player presses E
      │
      ▼
Client checks permissions (cosmetic filter — hides restricted options)
      │
      ▼
Player selects vehicle + bay
      │
      ▼
Client → Server: requestSpawn(locationId, vehicleIndex, bayIndex)
      │
      ▼
Server validates:
  • Location, vehicle, and bay exist
  • Anti-spam cooldown
  • ACE permission (IsPlayerAceAllowed)
  • Job permission (via framework)
      │
      ├── FAIL → Notify client with error
      │
      └── PASS → Server → Client: doSpawn(model, coords, heading)
                        │
                        ▼
                  Client creates vehicle, warps player in
```

---

## Licence

This project is open source. Feel free to modify and redistribute with credit to the original author.

---

*Built by Hadgebury — requires [ox_lib](https://github.com/overextended/ox_lib)*
