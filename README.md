# VehicleSpawnArea

A multi-location, server-authoritative vehicle spawner designed for FiveM. Out of the box, it operates seamlessly in standalone mode whilst automatically detecting **QBox**, **QBCore**, and **ESX** frameworks. It provides layered ACE and job-based permissions, configurable parking bays with dynamic occupancy detection, and an [ox_lib](https://github.com/overextended/ox_lib)-powered user interface.

---

## Features

- **Multi-Location Architecture** — Configure multiple garages across San Andreas, each with dedicated vehicles, parking bays, and permission requirements.
- **Framework Auto-Detection** — Automatically identifies active frameworks in order of priority (`QBox` → `QBCore` → `ESX` → `Standalone`) without manual toggles.
- **Layered Permissions** — Combines location-level access gates with optional per-vehicle permission overrides.
- **Flexible Permission Modes** — Choose between `'none'`, `'ace'`, `'job'`, or `'both'` (OR logic, where satisfying either ACE or job grants access).
- **Server-Authoritative Validation** — All spawn requests are independently verified server-side before vehicle entities are created, preventing unauthorized client execution.
- **Anti-Spam Cooldown** — Configurable server-enforced cooldown timer between consecutive spawn requests to prevent spam.
- **Dynamic Bay Occupancy** — Visual parking markers dynamically change colour (green for available, red for occupied) based on real-time vehicle collision checks.
- **Automatic Vehicle Replacement** — Optionally replaces unoccupied or player-owned vehicles currently in a bay when spawning a new vehicle.
- **Safe Entity Streaming** — Spawns vehicles within asynchronous coroutines, placing vehicles correctly upon the terrain and warping the player safely into the driver's seat.
- **Clean Lifecycle Management** — Automatically purges ox_lib interaction zones and UI prompts upon resource stop or restart.

---

## Dependencies

| Dependency | Status | Notes |
|---|---|---|
| [ox_lib](https://github.com/overextended/ox_lib) | **Mandatory** | Powers 3D zones, notifications, and context menus. |
| **QBox** / **QBCore** / **ESX** | **Optional** | Automatically detected for job-based access; standalone mode is used if absent. |

---

## Installation

1. Download or clone this repository into your FiveM server's `resources` directory:
   ```bash
   # Clone into your resources folder
   git clone https://github.com/Hadgebury/VehicleSpawnArea.git resources/[standalone]/VehicleSpawnArea
   ```
2. Ensure that `ox_lib` is started prior to `VehicleSpawnArea` in your `server.cfg`:
   ```cfg
   # Resource execution order
   ensure ox_lib
   ensure VehicleSpawnArea
   ```
3. Customise your garages, parking bays, and fleet definitions in [`shared/config.lua`](shared/config.lua).
4. If utilising ACE permissions, append the necessary access rules to your `server.cfg` (see [ACE Permissions](#ace-permissions)).
5. Start or restart your server to apply changes.

---

## Folder Structure

```
VehicleSpawnArea/
├── .gitignore              — Repository ignore rules for OS and editor artefacts
├── fxmanifest.lua          — Resource manifest and engine specifications
├── README.md               — Documentation and setup instructions
├── client/
│   └── main.lua            — Client-side zone handling, marker rendering, and vehicle creation
├── server/
│   └── main.lua            — Server-authoritative permission validation, cooldowns, and audit logs
└── shared/
    ├── config.lua          — All user-configurable settings, garages, bays, and fleet lists
    └── framework.lua       — Unified framework auto-detection and job extraction bridge
```

---

## Configuration

All user-facing options reside within [`shared/config.lua`](shared/config.lua).

### Global Settings

```lua
-- Select permission evaluation mode: 'none' | 'ace' | 'job' | 'both'
Config.PermissionMode = 'both'

-- Cooldown period (in seconds) enforced between consecutive spawns per player
Config.SpawnCooldown = 5

-- Detection radius (in metres) to check whether a parking bay is occupied by a vehicle
Config.OccupiedCheckRadius = 3.0

-- When true, spawning into an occupied bay deletes the existing unoccupied vehicle
Config.DeletePreviousVehicle = true

-- Enable verbose diagnostic logs in the server console (recommended only for debugging)
Config.Debug = false
```

### Adding and Configuring Garages

Garages are defined within the `Config.Locations` table. Both British English (`colour`) and legacy (`color`) keys are supported for marker styling:

```lua
Config.Locations = {
    -- Unique identifier for the garage location
    ['police_garage'] = {
        label = 'Mission Row Police Garage',

        -- Location-level permission requirements:
        -- Players must have one of these jobs (at or above minGrade) OR hold the ACE permission
        ace      = 'vehiclespawn.police',           -- ACE permission string (nil to bypass)
        jobs     = { 'police', 'sheriff' },         -- Permitted framework jobs (nil to bypass)
        minGrade = 0,                               -- Minimum job grade required (0 = any grade)

        -- Central interaction point where players interact to open the vehicle list
        menuPoint = {
            coords = vector3(425.41, -1015.89, 29.01), -- World coordinates
            radius = 3.0,                               -- Interaction sphere radius in metres
            marker = {
                type         = 20,                      -- Marker 20: vertical rotating cylinder
                scale        = 1.5,                     -- Diameter / scale of the marker
                colour       = { r = 0, g = 200, b = 255 }, -- Cyan blue RGB colour
                drawDistance = 15.0,                    -- Distance in metres at which marker renders
            },
        },

        -- Designated parking bays where vehicles are spawned
        bays = {
            {
                id      = 1,                            -- Unique bay number
                label   = 'Bay 1',                      -- Display label in menus
                coords  = vector3(426.77, -1028.15, 29.0), -- World coordinates
                heading = 5.51,                         -- Direction the vehicle will face (0.0–360.0)
                marker  = {
                    type   = 36,                        -- Marker 36: garage parking symbol
                    scale  = 1.5,                       -- Marker scale
                    colour = { r = 0, g = 255, b = 0 }, -- Green RGB colour when bay is available
                },
            },
        },

        -- List of vehicles available at this location
        vehicles = {
            {
                label = 'Incident Response Vehicle',
                model = 'police',                       -- Vehicle model name or hash
                -- Optional: vehicle-level permission overrides (stricter than location)
                -- ace      = 'vehiclespawn.police.supervisor',
                -- jobs     = { 'police' },
                -- minGrade = 3,
            },
        },
    },
}
```

---

## Permissions & Authorisation

### Layered Evaluation Model

Permissions operate in two distinct tiers:

1. **Location Tier** — Evaluated first. If the player does not meet location requirements, the garage remains completely inaccessible.
2. **Vehicle Tier** — Evaluated when a specific vehicle specifies its own `ace`, `jobs`, or `minGrade` properties. If a vehicle defines no custom permissions, it inherits access from the location tier.

When `Config.PermissionMode = 'both'`, a player needs to satisfy **either** the ACE check **or** the framework job check.

### ACE Permissions (`server.cfg`)

Grant permissions to groups or specific players within your `server.cfg`:

```cfg
# Grant group.police access to the police garage location
add_ace group.police vehiclespawn.police allow

# Grant group.ambulance access to the ambulance station location
add_ace group.ambulance vehiclespawn.ambulance allow

# Grant specialized ACE permission for restricted vehicles
add_ace group.police vehiclespawn.police.k9 allow

# Associate a player's identifier with a group
add_principal identifier.steam:110000100000001 group.police
add_principal identifier.license:40123456789abcdef0123456789abcdef0123456 group.ambulance
```

### Job Permissions (ESX / QBCore / QBox)

Job permissions are checked directly against the active framework's player data. No additional entries are required in `server.cfg`:

```lua
-- Allow any grade of police or sheriff
jobs     = { 'police', 'sheriff' },
minGrade = 0,

-- Restrict to senior staff (grade 3 and above)
jobs     = { 'police' },
minGrade = 3,
```

---

## Framework Support Matrix

The resource auto-detects the active framework upon startup in the following sequence:

| Priority | Framework | Target Resource | Notes |
|:---:|---|---|---|
| **1** | **QBox** | `qbx_core` | Uses modern modular exports; extracts job and numeric grade. |
| **2** | **QBCore** | `qb-core` | Uses shared core object; parses `PlayerData.job` table. |
| **3** | **ESX Legacy** | `es_extended` | Uses `getSharedObject`; compatible with `xPlayer.getJob()`. |
| **4** | **Standalone** | *Fallback* | Used when no framework is running; job checks are gracefully bypassed. |

---

## Vehicle Streaming Note (Addon vs Vanilla)

In the default configuration:
- Standard vehicles such as `'police'` and `'ambulance'` are base Grand Theft Auto V assets that work immediately on all servers.
- Custom models referenced in the configuration (such as `'BX21AWW'` and `'LX69AXC'`) are British emergency vehicle addon assets. If you do not stream these custom vehicle packs on your server, replace the spawn names with vanilla models (e.g. `'police2'`, `'police3'`, `'ambulance'`) or your own server's vehicle spawn codes.

---

## Operational Workflow

```
[ Player Approaches Area ]
          │
          ▼
Cosmetic Check: Player has location access?
  ├── NO  ──► UI prompt and markers are hidden
  └── YES ──► Markers render; [E] prompt displays
                    │
                    ▼
          [ Player Presses E ]
                    │
                    ▼
Displays ox_lib Context Menu (filtered to permitted vehicles)
                    │
                    ▼
          [ Player Selects Vehicle & Bay ]
                    │
                    ▼
Client sends Network Event: VehicleSpawnArea:requestSpawn(locationId, vehIdx, bayIdx)
                    │
                    ▼
┌─────────────────────────────────────────────────────────────┐
│             SERVER-AUTHORITATIVE VERIFICATION               │
│                                                             │
│  1. Validate locationId, vehIdx, and bayIdx exist in config │
│  2. Verify anti-spam cooldown has elapsed                   │
│  3. Authoritatively evaluate ACE and framework job perms    │
└─────────────────────────────────────────────────────────────┘
          │                                   │
       (FAIL)                              (PASS)
          │                                   │
          ▼                                   ▼
Notify Client (Error)               1. Record new spawn timestamp
                                    2. Output audit log to server console
                                    3. TriggerClientEvent: VehicleSpawnArea:doSpawn
                                              │
                                              ▼
                                    ┌───────────────────────────────────┐
                                    │        CLIENT SPAWN THREAD        │
                                    │                                   │
                                    │ 1. Asynchronously stream model    │
                                    │ 2. Clear bay if replacement is on │
                                    │ 3. Create vehicle & align terrain │
                                    │ 4. Warp player & start engine     │
                                    └───────────────────────────────────┘
```

---

## Licence

This project is open-source under standard permissive terms. You are welcome to adapt, modify, and integrate this resource into your FiveM community with credit to the original author.

---

*Authored by **Hadgebury** — Engineered for performance and security using [ox_lib](https://github.com/overextended/ox_lib).*
