--[[
╔══════════════════════════════════════════════════════════════════╗
║             VehicleSpawnArea — Resource Manifest                 ║
║                        fxmanifest.lua                            ║
╠══════════════════════════════════════════════════════════════════╣
║  Defines the resource metadata, engine requirements, and script  ║
║  loading manifest for FiveM.                                     ║
╚══════════════════════════════════════════════════════════════════╝
--]]

-- Manifest version and target game environment
fx_version 'cerulean'
game 'gta5'

-- Resource metadata
author 'Hadgebury'
description 'Multi-location Vehicle Spawn Area with framework support and layered permissions'
version '2.0.0'

-- Enable modern Lua 5.4 runtime (required for ox_lib and lexical scoping)
lua54 'yes'

-- Scripts loaded across both client and server environments
shared_scripts {
    '@ox_lib/init.lua',      -- ox_lib shared initialisation
    'shared/config.lua',     -- User-facing garage, bay, and permission configuration
    'shared/framework.lua',  -- Unified framework auto-detection and job extraction
}

-- Client-side logic scripts
client_scripts {
    'client/main.lua',       -- Zone registration, marker rendering, menus, and spawning
}

-- Server-side authoritative validation and events
server_scripts {
    'server/main.lua',       -- Authoritative permission checks, cooldowns, and audit logging
}

-- External resource dependencies required before this resource starts
dependencies {
    'ox_lib',
}
