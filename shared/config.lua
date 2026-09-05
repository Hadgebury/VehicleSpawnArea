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
║    'both'   — ACE OR job (player must pass at least one)         ║
║                                                                  ║
║  LAYERED PERMISSIONS                                             ║
║    1. Location-level — gates access to the entire garage         ║
║    2. Vehicle-level  — optional per-vehicle overrides            ║
║       If a vehicle has no permissions defined, the location      ║
║       check is sufficient to spawn it.                           ║
╚══════════════════════════════════════════════════════════════════╝
--]]

Config = {}

-- ============================================================
-- GLOBAL SETTINGS
-- ============================================================

--- Controls the overall permission system.
--- 'none' | 'ace' | 'job' | 'both'
--- When 'both', a player must satisfy ACE OR job (OR logic).
Config.PermissionMode = 'both'

--- Seconds a player must wait between consecutive spawn requests.
--- Prevents spam and abuse. Applied per player on the server.
Config.SpawnCooldown = 5

--- Radius in metres used to determine whether a parking bay is occupied.
--- A vehicle within this distance of the bay's coords will mark it as taken.
Config.OccupiedCheckRadius = 3.0

--- When true, spawning into an occupied bay will delete the existing vehicle
--- there (if the player owns it or it is empty) before placing the new one.
--- When false, occupied bays are simply disabled in the menu.
Config.DeletePreviousVehicle = true

--- When true, detailed permission check results and framework detection
--- are printed to the server console. Useful during setup; disable in production.
Config.Debug = false

-- ============================================================
-- SPAWN LOCATIONS
-- ============================================================
--[[
  Config.Locations is a keyed table. Each key is a unique identifier
  for a garage location (used internally for menus and network events).

  Each location must contain:
    label     (string)  — Display name shown in menus
    ace       (string)  — ACE permission string; nil to skip ACE check
    jobs      (table)   — Array of allowed job names; nil to skip job check
    minGrade  (number)  — Minimum job grade; 0 = any grade
    menuPoint (table)   — Central interaction point configuration
    bays      (table)   — Array of parking bay definitions
    vehicles  (table)   — Array of vehicle definitions

  Vehicles may optionally define their own ace / jobs / minGrade fields
  to apply stricter permissions on top of the location check.
--]]

Config.Locations = {

    -- ========================================
    -- POLICE GARAGE
    -- ========================================
    ['police_garage'] = {
        label = 'Police Garage',

        -- Location-level: a player must be in the police or sheriff job,
        -- OR hold the vehiclespawn.police ACE permission, to access this garage.
        ace      = 'vehiclespawn.police',
        jobs     = { 'police', 'sheriff' },
        minGrade = 0,

        -- The central point where the player presses E to open the vehicle menu.
        menuPoint = {
            coords = vector3(425.41, -1015.89, 29.01),
            radius = 3.0,               -- Interaction radius in metres
            marker = {
                type         = 20,      -- Marker type 20 = vertical rotating cylinder
                scale        = 1.5,     -- Size of the marker
                color        = { r = 0, g = 200, b = 255 },   -- Bright blue
                drawDistance = 15.0,    -- Distance at which the marker becomes visible
            },
        },

        -- Parking bays where vehicles will physically be created.
        -- Markers change from green (available) to red (occupied) automatically.
        bays = {
            {
                id      = 1,
                label   = 'Bay 1',
                coords  = vector3(426.77, -1028.15, 29.0),
                heading = 5.51,         -- Direction the vehicle will face (0–360)
                marker  = {
                    type  = 36,         -- Marker type 36 = garage/parking symbol
                    scale = 1.5,
                    color = { r = 0, g = 255, b = 0 },  -- Green when available
                },
            },
            {
                id      = 2,
                label   = 'Bay 2',
                coords  = vector3(430.88, -1027.11, 28.93),
                heading = 5.02,
                marker  = {
                    type  = 36,
                    scale = 1.5,
                    color = { r = 0, g = 255, b = 0 },
                },
            },
        },

        -- Vehicles available at this location.
        -- Each entry requires a label (display name) and a model (spawn code).
        -- Per-vehicle permissions are optional; comment them out to inherit
        -- the location-level permissions instead.
        vehicles = {
            {
                label = '2020 Mondeo Dog Section',
                model = 'BX21AWW',
                -- Uncomment to restrict this vehicle further (e.g. K9 officers only):
                -- ace      = 'vehiclespawn.police.k9',
                -- jobs     = { 'police' },
                -- minGrade = 2,
            },
            {
                label = 'IRV',
                model = 'police',
                -- No per-vehicle permissions — location check is sufficient.
            },
        },
    },

    -- ========================================
    -- AMBULANCE STATION
    -- ========================================
    ['ambulance_station'] = {
        label = 'Ambulance Station',

        ace      = 'vehiclespawn.ambulance',
        jobs     = { 'ambulance', 'doctor' },
        minGrade = 0,

        menuPoint = {
            coords = vector3(295.12, -587.36, 43.26),
            radius = 3.0,
            marker = {
                type         = 20,
                scale        = 1.5,
                color        = { r = 255, g = 50, b = 50 },   -- Red
                drawDistance = 15.0,
            },
        },

        bays = {
            {
                id      = 1,
                label   = 'Bay 1',
                coords  = vector3(290.32, -590.15, 43.26),
                heading = 340.0,
                marker  = {
                    type  = 36,
                    scale = 1.5,
                    color = { r = 0, g = 255, b = 0 },
                },
            },
        },

        vehicles = {
            {
                label = 'Ambulance',
                model = 'LX69AXC',
            },
        },
    },

    -- ========================================
    -- EXAMPLE: CIVILIAN GARAGE (open to all)
    -- ========================================
    -- Uncomment and populate to add an unrestricted public garage.
    -- ['civilian_garage'] = {
    --     label    = 'Civilian Garage',
    --     ace      = nil,     -- No ACE required
    --     jobs     = nil,     -- No job required
    --     minGrade = 0,
    --     menuPoint = {
    --         coords = vector3(0.0, 0.0, 0.0),
    --         radius = 3.0,
    --         marker = { type = 20, scale = 1.5, color = { r = 255, g = 165, b = 0 }, drawDistance = 15.0 },
    --     },
    --     bays = {
    --         { id = 1, label = 'Bay 1', coords = vector3(0.0, 0.0, 0.0), heading = 0.0,
    --           marker = { type = 36, scale = 1.5, color = { r = 0, g = 255, b = 0 } } },
    --     },
    --     vehicles = {
    --         { label = 'Sultan RS', model = 'sultanrs' },
    --     },
    -- },
}
