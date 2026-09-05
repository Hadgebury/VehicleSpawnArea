--[[
╔══════════════════════════════════════════════════════════════════╗
║                   VehicleSpawnArea — Config                      ║
║                      shared/config.lua                           ║
╠══════════════════════════════════════════════════════════════════╣
║  All user-facing configuration lives here.                       ║
║  This file is loaded on both the client and the server.          ║
║                                                                  ║
║  PERMISSION MODES                                                ║
║    'none'   — No permission checks; everyone can spawn anything  ║
║    'ace'    — ACE permissions only (server.cfg)                  ║
║    'job'    — Framework job checks only (ESX / QBCore / QBox)    ║
║    'both'   — ACE OR job (player must satisfy at least one)      ║
║                                                                  ║
║  LAYERED PERMISSIONS                                             ║
║    1. Location-level — gates access to the entire garage         ║
║    2. Vehicle-level  — optional per-vehicle overrides            ║
║       If a vehicle has no permissions defined, the location      ║
║       check is sufficient to spawn it.                           ║
║                                                                  ║
║  NOTE: All non-code text and comments adhere to British English. ║
║  Both 'colour' and 'color' keys are supported for marker tables. ║
╚══════════════════════════════════════════════════════════════════╝
--]]

Config = {}

-- ============================================================
-- GLOBAL SETTINGS
-- ============================================================

--- Controls the overall permission system.
--- Supported options: 'none' | 'ace' | 'job' | 'both'
--- When set to 'both', satisfying either ACE OR framework job is sufficient (OR logic).
Config.PermissionMode = 'both'

--- Cooldown period (in seconds) enforced between consecutive vehicle spawn requests.
--- Prevents command spam and server desynchronisation. Applied per player on the server.
Config.SpawnCooldown = 5

--- Radius in metres used to determine whether a parking bay is occupied.
--- Any vehicle entity detected within this distance of the bay coordinates marks it as taken.
Config.OccupiedCheckRadius = 3.0

--- When true, attempting to spawn into an occupied bay will safely delete the
--- existing vehicle (if unoccupied or owned by the player) before creating the new one.
--- When false, occupied bays are marked as disabled in the selection menu.
Config.DeletePreviousVehicle = true

--- When true, detailed permission evaluation diagnostics and framework detection
--- messages are output to the server console. Useful during setup; disable in production.
Config.Debug = false

-- ============================================================
-- SPAWN LOCATIONS CONFIGURATION
-- ============================================================
--[[
  Config.Locations is a keyed dictionary. Each key is a unique identifier
  for a garage location (used internally for menus and network events).

  Each location must contain:
    label     (string)  — Display name shown in menus and notifications
    ace       (string)  — ACE permission string (e.g. 'vehiclespawn.police'); nil to bypass
    jobs      (table)   — Array of allowed job strings (e.g. { 'police' }); nil to bypass
    minGrade  (number)  — Minimum required job grade (0 = any grade)
    menuPoint (table)   — Central interaction point configuration
    bays      (table)   — Array of individual parking bay definitions
    vehicles  (table)   — Array of vehicle definitions available at this location

  Vehicles may optionally define their own ace / jobs / minGrade fields
  to apply stricter permissions on top of the location check.
--]]

Config.Locations = {

    -- ========================================================
    -- MISSION ROW POLICE GARAGE
    -- ========================================================
    ['police_garage'] = {
        label = 'Police Garage',

        -- Location-level permission gate:
        -- Players must possess the 'police' or 'sheriff' job, OR hold the
        -- 'vehiclespawn.police' ACE permission, to access this garage.
        ace      = 'vehiclespawn.police',
        jobs     = { 'police', 'sheriff' },
        minGrade = 0,

        -- Central interaction point where players press [E] to open the garage menu.
        menuPoint = {
            coords = vector3(425.41, -1015.89, 29.01),
            radius = 3.0,               -- Interaction radius in metres
            marker = {
                type         = 20,      -- Marker type 20: vertical rotating cylinder
                scale        = 1.5,     -- Diameter / scale of the marker
                colour       = { r = 0, g = 200, b = 255 },  -- Bright cyan blue
                drawDistance = 15.0,    -- Visible rendering distance in metres
            },
        },

        -- Individual parking bays where vehicles are physically spawned.
        -- Bay markers dynamically switch to red when occupied by a vehicle.
        bays = {
            {
                id      = 1,
                label   = 'Bay 1',
                coords  = vector3(426.77, -1028.15, 29.0),
                heading = 5.51,         -- Heading angle in degrees (0.0–360.0)
                marker  = {
                    type   = 36,        -- Marker type 36: garage / parking bay symbol
                    scale  = 1.5,
                    colour = { r = 0, g = 255, b = 0 },  -- Green when free
                },
            },
            {
                id      = 2,
                label   = 'Bay 2',
                coords  = vector3(430.88, -1027.11, 28.93),
                heading = 5.02,
                marker  = {
                    type   = 36,
                    scale  = 1.5,
                    colour = { r = 0, g = 255, b = 0 },
                },
            },
        },

        -- Vehicles available at this garage.
        -- Note: 'BX21AWW' is a custom British emergency vehicle model;
        -- replace with standard vanilla spawn names (e.g. 'police', 'police2',
        -- 'police3') if you are not streaming custom addon vehicles.
        vehicles = {
            {
                label = '2020 Mondeo Dog Section',
                model = 'BX21AWW',
                -- Optional vehicle-level restriction override example:
                -- ace      = 'vehiclespawn.police.k9',
                -- jobs     = { 'police' },
                -- minGrade = 2,
            },
            {
                label = 'Incident Response Vehicle (IRV)',
                model = 'police',
                -- No specific vehicle overrides: location check is sufficient
            },
        },
    },

    -- ========================================================
    -- PILLBOX HILL AMBULANCE STATION
    -- ========================================================
    ['ambulance_station'] = {
        label = 'Ambulance Station',

        -- Location-level permission gate:
        -- Access restricted to ambulance / medical staff or holders of the ACE permission.
        ace      = 'vehiclespawn.ambulance',
        jobs     = { 'ambulance', 'doctor' },
        minGrade = 0,

        -- Central interaction point for opening the ambulance fleet menu.
        menuPoint = {
            coords = vector3(295.12, -587.36, 43.26),
            radius = 3.0,
            marker = {
                type         = 20,
                scale        = 1.5,
                colour       = { r = 255, g = 50, b = 50 },  -- Bright red
                drawDistance = 15.0,
            },
        },

        -- Parking bays allocated for emergency medical vehicles.
        bays = {
            {
                id      = 1,
                label   = 'Bay 1',
                coords  = vector3(290.32, -590.15, 43.26),
                heading = 340.0,
                marker  = {
                    type   = 36,
                    scale  = 1.5,
                    colour = { r = 0, g = 255, b = 0 },
                },
            },
        },

        -- Vehicles available at the ambulance station.
        -- Note: 'LX69AXC' is an addon UK ambulance; replace with 'ambulance'
        -- if testing without addon emergency vehicle packs.
        vehicles = {
            {
                label = 'Emergency Ambulance (Custom)',
                model = 'LX69AXC',
            },
            {
                label = 'Standard Ambulance (Vanilla)',
                model = 'ambulance',
            },
        },
    },

    -- ========================================================
    -- TEMPLATE: UNRESTRICTED PUBLIC / CIVILIAN GARAGE
    -- ========================================================
    -- Uncomment and adjust coordinates to deploy a public garage open to all players.
    -- ['civilian_garage'] = {
    --     label    = 'Legion Square Garage',
    --     ace      = nil,     -- Nil indicates no ACE permission required
    --     jobs     = nil,     -- Nil indicates no framework job required
    --     minGrade = 0,
    --     menuPoint = {
    --         coords = vector3(215.12, -805.23, 30.50),
    --         radius = 3.0,
    --         marker = {
    --             type         = 20,
    --             scale        = 1.5,
    --             colour       = { r = 255, g = 165, b = 0 },  -- Amber
    --             drawDistance = 15.0,
    --         },
    --     },
    --     bays = {
    --         {
    --             id      = 1,
    --             label   = 'Bay 1',
    --             coords  = vector3(218.45, -810.12, 30.50),
    --             heading = 90.0,
    --             marker  = {
    --                 type   = 36,
    --                 scale  = 1.5,
    --                 colour = { r = 0, g = 255, b = 0 },
    --             },
    --         },
    --     },
    --     vehicles = {
    --         { label = 'Karin Sultan RS', model = 'sultanrs' },
    --         { label = 'Bravado Buffalo STX', model = 'buffalos' },
    --     },
    -- },
}
