--[[
╔══════════════════════════════════════════════════════════════════╗
║                  VehicleSpawnArea — Client                       ║
║                      client/main.lua                             ║
╠══════════════════════════════════════════════════════════════════╣
║  Handles all client-side logic:                                  ║
║    • ox_lib zone creation (per location and per bay)             ║
║    • Distance-gated marker drawing                               ║
║    • Permission-filtered context menus                           ║
║    • Vehicle spawn requests (server-authoritative)               ║
║    • Receiving and executing server-approved spawns              ║
║                                                                  ║
║  NOTE: Permission checks here are COSMETIC only — they filter    ║
║  what the player sees in menus. The server performs the          ║
║  authoritative validation before any vehicle is created.         ║
╚══════════════════════════════════════════════════════════════════╝
--]]

-- ============================================================
-- LOCAL STATE
-- ============================================================

--- Holds references to every ox_lib zone created at startup,
--- allowing them to be destroyed cleanly if required.
local activeZones = {}

-- ============================================================
-- PERMISSION CHECKING (Client-side — cosmetic filter only)
-- ============================================================

--- Checks whether the local player passes a permission gate.
--- Used to hide restricted locations or vehicles in menus.
--- The server re-validates before any actual spawn occurs.
---
---@param perms table  Config table with optional fields: ace, jobs, minGrade
---@return boolean     true if the player should see / use this option
local function HasPermission(perms)
    -- 'none' mode: skip all checks entirely
    if Config.PermissionMode == 'none' then
        return true
    end

    local aceOk = false
    local jobOk = false

    -- ACE check — IsPlayerAceAllowed works for the local player on the client
    if perms.ace then
        aceOk = IsPlayerAceAllowed(PlayerId(), perms.ace)
    else
        -- No ACE string configured → ACE check passes automatically
        aceOk = true
    end

    -- Job check — uses the unified Framework API from shared/framework.lua
    if perms.jobs and #perms.jobs > 0 then
        local playerJob = Framework.GetPlayerJob()

        if playerJob then
            -- Iterate allowed jobs; pass if any match the player's job and grade
            for _, allowedJob in ipairs(perms.jobs) do
                if playerJob.name == allowedJob
                and playerJob.grade >= (perms.minGrade or 0) then
                    jobOk = true
                    break
                end
            end
        else
            -- No framework running (standalone) — skip job check
            if Framework.name == 'standalone' then
                jobOk = true
            end
        end
    else
        -- No jobs list configured → job check passes automatically
        jobOk = true
    end

    -- Evaluate against the active permission mode
    if Config.PermissionMode == 'ace' then
        return aceOk
    elseif Config.PermissionMode == 'job' then
        return jobOk
    elseif Config.PermissionMode == 'both' then
        -- OR logic: satisfying either check is sufficient
        return aceOk or jobOk
    end

    return false
end

--- Checks whether the player can spawn a specific vehicle at a given location.
--- Applies the layered permission model: location → vehicle.
---
---@param location table  The location config table
---@param vehicle  table  The vehicle config table
---@return boolean
local function CanSpawnVehicle(location, vehicle)
    -- Must pass the location gate before vehicle-level checks run
    if not HasPermission(location) then
        return false
    end

    -- If the vehicle defines its own permissions, check those on top
    if vehicle.ace or (vehicle.jobs and #vehicle.jobs > 0) then
        return HasPermission(vehicle)
    end

    -- No vehicle-level permissions — location check was sufficient
    return true
end

-- ============================================================
-- BAY OCCUPANCY
-- ============================================================

--- Returns true if any vehicle is within Config.OccupiedCheckRadius of coords.
---@param coords vector3
---@return boolean
local function IsBayOccupied(coords)
    local vehicles = GetGamePool('CVehicle')
    for _, vehicle in ipairs(vehicles) do
        if #(GetEntityCoords(vehicle) - coords) < Config.OccupiedCheckRadius then
            return true
        end
    end
    return false
end

--- Attempts to delete the vehicle currently occupying a bay.
--- Only removes the vehicle if the local player is its network owner
--- or if no player is currently sitting in it.
---
---@param coords vector3
---@return boolean  true if a vehicle was successfully deleted
local function DeleteVehicleInBay(coords)
    local vehicles = GetGamePool('CVehicle')
    for _, vehicle in ipairs(vehicles) do
        if #(GetEntityCoords(vehicle) - coords) < Config.OccupiedCheckRadius then
            -- Only delete if we own it or it is unoccupied
            local driverPed = GetPedInVehicleSeat(vehicle, -1)
            if NetworkGetEntityOwner(vehicle) == PlayerId() or driverPed == 0 then
                SetEntityAsMissionEntity(vehicle, true, true)
                DeleteVehicle(vehicle)
                return true
            end
        end
    end
    return false
end

-- ============================================================
-- VEHICLE SPAWNING
-- ============================================================

--- Spawns a vehicle at the specified coordinates and heading.
--- Called only after the server has validated and authorised the request.
---
---@param model   string|number  Vehicle model name or joaat hash
---@param coords  vector3        World position to spawn the vehicle
---@param heading number         Direction the vehicle should face (0–360)
local function SpawnVehicle(model, coords, heading)
    -- Resolve the model name to a numeric hash if a string was passed
    local hash = type(model) == 'string' and joaat(model) or model

    if not IsModelInCdimage(hash) then
        lib.notify({ title = 'Error', description = 'Invalid vehicle model', type = 'error' })
        return
    end

    -- If configured to do so, clear any existing vehicle from the bay first
    if Config.DeletePreviousVehicle then
        DeleteVehicleInBay(coords)
    end

    -- Re-check occupancy after any deletion attempt
    if IsBayOccupied(coords) then
        lib.notify({ title = 'Error', description = 'Bay was just occupied!', type = 'error' })
        return
    end

    -- Request the model from the game's streaming system
    RequestModel(hash)

    -- Wait until the model has loaded, with a 5-second timeout to prevent
    -- the thread hanging indefinitely if the model is invalid or missing
    local timeout = GetGameTimer() + 5000
    while not HasModelLoaded(hash) do
        if GetGameTimer() > timeout then
            lib.notify({ title = 'Error', description = 'Vehicle model failed to load', type = 'error' })
            return
        end
        Wait(10)
    end

    -- Create the vehicle in the world
    local vehicle = CreateVehicle(hash, coords.x, coords.y, coords.z, heading, true, false)

    -- Release the model from memory now that the vehicle entity exists
    SetModelAsNoLongerNeeded(hash)

    if vehicle and DoesEntityExist(vehicle) then
        -- Warp the player into the driver's seat (-1 = driver)
        TaskWarpPedIntoVehicle(PlayerPedId(), vehicle, -1)
        -- Start the engine immediately so the player doesn't need to press W first
        SetVehicleEngineOn(vehicle, true, true, false)
        -- Ensure the vehicle sits correctly on the ground after spawning
        SetVehicleOnGroundProperly(vehicle)

        lib.notify({
            title       = 'Vehicle Spawned',
            description = ('%s ready'):format(GetDisplayNameFromVehicleModel(hash)),
            type        = 'success',
        })
    end
end

-- ============================================================
-- NETWORK EVENT HANDLERS
-- ============================================================

--- Triggered by the server after it has validated the spawn request.
--- Passes the model, spawn coordinates, and heading back to this client.
RegisterNetEvent('VehicleSpawnArea:doSpawn', function(model, coords, heading)
    SpawnVehicle(model, vector3(coords.x, coords.y, coords.z), heading)
end)

--- Receives notifications sent by the server (e.g. cooldown messages,
--- permission-denied responses) and displays them via ox_lib.
RegisterNetEvent('VehicleSpawnArea:notify', function(data)
    lib.notify(data)
end)

-- ============================================================
-- MENU SYSTEMS
-- ============================================================

--- Opens the main vehicle selection menu for a location.
--- Called when the player presses E at the central menu interaction point.
--- Filters the vehicle list so only permitted vehicles are shown.
---
---@param locationId string  The location's key in Config.Locations
---@param location   table   The location config table
local function OpenVehicleMenu(locationId, location)
    local options = {}

    for vehIdx, vehicle in ipairs(location.vehicles) do
        if CanSpawnVehicle(location, vehicle) then
            -- Capture loop variables explicitly to avoid closure issues
            local capturedIdx     = vehIdx
            local capturedVehicle = vehicle

            table.insert(options, {
                title       = capturedVehicle.label,
                description = 'Select a bay to spawn this vehicle',
                icon        = 'car',
                onSelect    = function()
                    OpenBaySelectionMenu(locationId, location, capturedIdx, capturedVehicle)
                end,
            })
        end
    end

    if #options == 0 then
        lib.notify({
            title       = 'No Access',
            description = 'You do not have permission to spawn any vehicles here',
            type        = 'error',
        })
        return
    end

    lib.registerContext({
        id      = 'vsa_vehicle_menu_' .. locationId,
        title   = location.label .. ' — Vehicles',
        options = options,
    })
    lib.showContext('vsa_vehicle_menu_' .. locationId)
end

--- Opens the bay selection submenu after the player has chosen a vehicle.
--- Each bay is listed with its current availability (available / occupied).
---
---@param locationId string  The location's key in Config.Locations
---@param location   table   The location config table
---@param vehIdx     number  Index of the selected vehicle in location.vehicles
---@param vehicle    table   The selected vehicle config table
function OpenBaySelectionMenu(locationId, location, vehIdx, vehicle)
    local options = {}

    for bayIdx, bay in ipairs(location.bays) do
        local occupied = IsBayOccupied(bay.coords)
        -- A bay can be used if it is free, or if we can replace the vehicle inside
        local canUse   = not occupied or Config.DeletePreviousVehicle

        local capturedBayIdx = bayIdx

        table.insert(options, {
            title       = bay.label,
            description = occupied
                and (Config.DeletePreviousVehicle and '⚠️ Occupied — will replace' or '🚗 Occupied')
                or  '🅿️ Available',
            icon        = occupied and 'car' or 'square-parking',
            disabled    = not canUse,
            onSelect    = canUse and function()
                -- Send the validated indices to the server; it will check
                -- permissions and authorise (or deny) the spawn
                TriggerServerEvent('VehicleSpawnArea:requestSpawn', locationId, vehIdx, capturedBayIdx)
            end or nil,
        })
    end

    lib.registerContext({
        id      = 'vsa_bay_menu_' .. locationId,
        title   = vehicle.label .. ' — Select Bay',
        menu    = 'vsa_vehicle_menu_' .. locationId,    -- Back button returns here
        options = options,
    })
    lib.showContext('vsa_bay_menu_' .. locationId)
end

--- Opens a combined vehicle + bay menu when the player interacts directly
--- at a parking bay, allowing them to choose a vehicle without visiting
--- the central menu point first.
---
---@param locationId string  The location's key in Config.Locations
---@param location   table   The location config table
---@param bay        table   The bay config table
---@param bayIdx     number  Index of the bay in location.bays
local function OpenBayDirectMenu(locationId, location, bay, bayIdx)
    -- If the bay is occupied and we are not configured to replace, bail out early
    if IsBayOccupied(bay.coords) and not Config.DeletePreviousVehicle then
        lib.notify({
            title       = 'Bay Occupied',
            description = 'This bay is currently in use',
            type        = 'error',
        })
        return
    end

    local occupied = IsBayOccupied(bay.coords)
    local options  = {}

    for vehIdx, vehicle in ipairs(location.vehicles) do
        if CanSpawnVehicle(location, vehicle) then
            local capturedIdx = vehIdx

            table.insert(options, {
                title       = vehicle.label,
                description = occupied
                    and ('Spawn in %s (will replace)'):format(bay.label)
                    or  ('Spawn in %s'):format(bay.label),
                icon        = 'car',
                onSelect    = function()
                    TriggerServerEvent('VehicleSpawnArea:requestSpawn', locationId, capturedIdx, bayIdx)
                end,
            })
        end
    end

    if #options == 0 then
        lib.notify({
            title       = 'No Access',
            description = 'You do not have permission to spawn any vehicles here',
            type        = 'error',
        })
        return
    end

    lib.registerContext({
        id      = 'vsa_bay_direct_' .. locationId .. '_' .. bayIdx,
        title   = ('%s — %s'):format(location.label, bay.label),
        options = options,
    })
    lib.showContext('vsa_bay_direct_' .. locationId .. '_' .. bayIdx)
end

-- ============================================================
-- MARKER DRAWING
-- ============================================================
--[[
  Marker drawing is distance-gated to minimise GPU and CPU overhead:
    • The thread sleeps for 500 ms when no location is within 80 metres.
    • It drops to Wait(0) (every frame) only when the player is close enough
      for markers to be visible, preventing unnecessary world scans when the
      player is far away.
--]]

CreateThread(function()
    while true do
        -- Default to a long sleep; shortened when near a location
        local sleep         = 500
        local playerCoords  = GetEntityCoords(PlayerPedId())

        for _, location in pairs(Config.Locations) do
            local menuPoint  = location.menuPoint
            local distToMenu = #(playerCoords - menuPoint.coords)

            -- Only process markers for this location if within range
            if distToMenu < 80.0 then
                sleep = 0   -- Switch to per-frame updates while nearby

                -- Draw the central menu point marker
                if distToMenu < menuPoint.marker.drawDistance then
                    DrawMarker(
                        menuPoint.marker.type,
                        menuPoint.coords.x,
                        menuPoint.coords.y,
                        menuPoint.coords.z - 0.5,   -- Slight downward offset looks cleaner
                        0.0, 0.0, 0.0,              -- No directional movement
                        0.0, 0.0, 0.0,              -- No rotation
                        menuPoint.marker.scale,
                        menuPoint.marker.scale,
                        menuPoint.marker.scale,
                        menuPoint.marker.color.r,
                        menuPoint.marker.color.g,
                        menuPoint.marker.color.b,
                        200,                        -- Alpha (0–255)
                        false, true, 2, nil, nil, false
                    )
                end

                -- Draw individual bay markers, changing colour based on occupancy
                for _, bay in ipairs(location.bays) do
                    if #(playerCoords - bay.coords) < 25.0 then
                        local isOccupied = IsBayOccupied(bay.coords)

                        DrawMarker(
                            bay.marker.type,
                            bay.coords.x, bay.coords.y, bay.coords.z,
                            0.0, 0.0, 0.0,
                            0.0, 0.0, 0.0,
                            bay.marker.scale,
                            bay.marker.scale,
                            bay.marker.scale,
                            -- Red (255, 0, 0) when occupied; configured colour when free
                            isOccupied and 255 or bay.marker.color.r,
                            isOccupied and 0   or bay.marker.color.g,
                            isOccupied and 0   or bay.marker.color.b,
                            200,
                            false, true, 2, nil, nil, false
                        )
                    end
                end
            end
        end

        Wait(sleep)
    end
end)

-- ============================================================
-- ZONE CREATION (ox_lib)
-- ============================================================
--[[
  One sphere zone is created for each location's menu point, plus one
  per parking bay. Zones drive the on-screen [E] text UI prompts.

  A short initial Wait(500) gives the framework objects time to be ready
  before any permission checks run during zone enter callbacks.
--]]

CreateThread(function()
    Wait(500)   -- Allow framework exports to initialise before zones are registered

    for locationId, location in pairs(Config.Locations) do

        -- ---- Central menu point zone ----
        local menuZone = lib.zones.sphere({
            coords  = location.menuPoint.coords,
            radius  = location.menuPoint.radius,
            onEnter = function()
                -- Only show the prompt if the player has access to this location
                if HasPermission(location) then
                    lib.showTextUI(
                        '[E] ' .. location.label,
                        { position = 'left-center', icon = 'warehouse' }
                    )
                end
            end,
            onExit  = function()
                lib.hideTextUI()
            end,
        })
        table.insert(activeZones, menuZone)

        -- ---- Parking bay zones ----
        for bayIdx, bay in ipairs(location.bays) do
            local capturedBayIdx = bayIdx  -- Capture index to avoid closure issues

            local bayZone = lib.zones.sphere({
                coords  = bay.coords,
                radius  = 2.5,
                onEnter = function()
                    if HasPermission(location) then
                        lib.showTextUI(
                            ('[E] %s — %s'):format(location.label, bay.label),
                            { position = 'left-center', icon = 'square-parking' }
                        )
                    end
                end,
                onExit  = function()
                    lib.hideTextUI()
                end,
            })

            -- Store metadata on the zone object for potential future use
            bayZone._vsaLocationId = locationId
            bayZone._vsaBayIdx     = capturedBayIdx
            table.insert(activeZones, bayZone)
        end
    end
end)

-- ============================================================
-- KEY HANDLING
-- ============================================================
--[[
  Polls for the E key (control 38) each frame. When pressed, the script
  checks whether the player is inside a menu point zone or a bay zone
  and opens the appropriate menu.

  `goto continue` is used to break out of the outer location loop once
  an interaction has been handled, preventing double-menu opens when
  zones are close together.
--]]

CreateThread(function()
    while true do
        Wait(0)

        if IsControlJustReleased(0, 38) then    -- 38 = E key
            local playerCoords = GetEntityCoords(PlayerPedId())

            for locationId, location in pairs(Config.Locations) do

                -- Check if the player is at the central menu interaction point
                if #(playerCoords - location.menuPoint.coords) < location.menuPoint.radius then
                    if HasPermission(location) then
                        OpenVehicleMenu(locationId, location)
                    else
                        lib.notify({
                            title       = 'No Access',
                            description = 'You do not have permission to use this garage',
                            type        = 'error',
                        })
                    end
                    goto continue   -- Skip remaining locations once handled
                end

                -- Check if the player is standing at one of the parking bays
                for bayIdx, bay in ipairs(location.bays) do
                    if #(playerCoords - bay.coords) < 2.5 then
                        if HasPermission(location) then
                            OpenBayDirectMenu(locationId, location, bay, bayIdx)
                        else
                            lib.notify({
                                title       = 'No Access',
                                description = 'You do not have permission to use this garage',
                                type        = 'error',
                            })
                        end
                        goto continue   -- Skip remaining locations once handled
                    end
                end
            end

            -- Label jumped to after an interaction is handled; Lua 5.4 goto target
            ::continue::
        end
    end
end)
