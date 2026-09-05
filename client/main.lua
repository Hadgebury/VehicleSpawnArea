--[[
╔══════════════════════════════════════════════════════════════════╗
║                  VehicleSpawnArea — Client                       ║
║                      client/main.lua                             ║
╠══════════════════════════════════════════════════════════════════╣
║  Handles all client-side operations:                             ║
║    • ox_lib zone management with automatic cleanup on restart    ║
║    • Distance-gated, permission-filtered marker rendering        ║
║    • UI text prompts and permission-filtered context menus       ║
║    • Server-authoritative vehicle spawn dispatch                 ║
║    • Safe vehicle entity creation, model streaming, and warping  ║
║                                                                  ║
║  CRITICAL STABILITY NOTES:                                       ║
║    • All server-approved spawn handlers run in coroutines        ║
║      (CreateThread) to avoid C-call boundary yield crashes.      ║
║    • onResourceStop cleans up all ox_lib zones and active text   ║
║      prompts to prevent ghost triggers across resource restarts. ║
║                                                                  ║
║  Note: All comments and non-code text adhere to British English. ║
╚══════════════════════════════════════════════════════════════════╝
--]]

-- ============================================================
-- LOCAL STATE MANAGEMENT
-- ============================================================

--- Holds references to all registered ox_lib zones for clean lifecycle teardown.
local activeZones = {}

--- Tracks the current active interaction zone the player is standing inside.
--- Set on zone entry, cleared on zone exit. Eliminates redundant distance scans.
local currentZone = nil

-- Forward declaration of local menu functions to allow mutual referencing
local OpenVehicleMenu
local OpenBaySelectionMenu
local OpenBayDirectMenu

-- ============================================================
-- HELPER: COLOUR RESOLUTION
-- ============================================================

--- Resolves RGB colour values from a marker configuration table,
--- transparently supporting both British ('colour') and legacy ('color') keys.
---
---@param marker table  The marker configuration table
---@return table        RGB table with { r = number, g = number, b = number }
local function GetMarkerColour(marker)
    local col = marker.colour or marker.color or { r = 0, g = 255, b = 0 }
    return {
        r = col.r or 0,
        g = col.g or 255,
        b = col.b or 0,
    }
end

-- ============================================================
-- PERMISSION FILTERING (Client-Side — Cosmetic Only)
-- ============================================================

--- Evaluates whether the local player satisfies permission requirements.
--- Used purely to filter menu items and hide unauthorized garages.
--- Note: The server performs authoritative validation before any spawn occurs.
---
---@param perms table  Configuration table containing optional ace, jobs, minGrade
---@return boolean     true if the local player satisfies the permission gate
local function HasPermission(perms)
    -- If permission mode is 'none', permit access unconditionally
    if Config.PermissionMode == 'none' then
        return true
    end

    local aceOk = false
    local jobOk = false

    -- --------------------------------------------------------
    -- 1. Client-Side ACE Check
    -- --------------------------------------------------------
    if perms.ace then
        aceOk = IsPlayerAceAllowed(PlayerId(), perms.ace)
    else
        aceOk = true
    end

    -- --------------------------------------------------------
    -- 2. Client-Side Framework Job Check
    -- --------------------------------------------------------
    if perms.jobs and #perms.jobs > 0 then
        local playerJob = Framework.GetPlayerJob()

        if playerJob then
            local requiredGrade = perms.minGrade or 0

            for _, allowedJob in ipairs(perms.jobs) do
                if playerJob.name == allowedJob and playerJob.grade >= requiredGrade then
                    jobOk = true
                    break
                end
            end
        else
            -- If standalone mode is active, bypass job check
            if Framework.name == 'standalone' then
                jobOk = true
            end
        end
    else
        jobOk = true
    end

    -- --------------------------------------------------------
    -- 3. Mode Evaluation
    -- --------------------------------------------------------
    if Config.PermissionMode == 'ace' then
        return aceOk
    elseif Config.PermissionMode == 'job' then
        return jobOk
    elseif Config.PermissionMode == 'both' then
        return aceOk or jobOk
    end

    return false
end

--- Determines whether the local player can spawn a specific vehicle at a location.
--- Implements layered logic: location permission gate -> vehicle override gate.
---
---@param location table  The garage location configuration table
---@param vehicle  table  The vehicle configuration table
---@return boolean        true if the vehicle should be presented in the menu
local function CanSpawnVehicle(location, vehicle)
    -- Must pass the primary location check first
    if not HasPermission(location) then
        return false
    end

    -- If the vehicle defines specific restrictions, evaluate them
    if vehicle.ace or (vehicle.jobs and #vehicle.jobs > 0) then
        return HasPermission(vehicle)
    end

    -- Vehicle has no specific restrictions; inherits location approval
    return true
end

-- ============================================================
-- PARKING BAY OCCUPANCY & CLEANUP
-- ============================================================

--- Checks whether any vehicle entity is currently within the detection radius of coordinates.
---
---@param coords vector3  The bay coordinates to check
---@return boolean        true if a valid vehicle is occupying the bay
local function IsBayOccupied(coords)
    local vehicles = GetGamePool('CVehicle')
    for _, vehicle in ipairs(vehicles) do
        if DoesEntityExist(vehicle) and #(GetEntityCoords(vehicle) - coords) < Config.OccupiedCheckRadius then
            return true
        end
    end
    return false
end

--- Attempts to delete any existing vehicle occupying a parking bay.
--- Requests network control and ensures passengers are not displaced.
---
---@param coords vector3  The bay coordinates
---@return boolean        true if an occupying vehicle was successfully deleted
local function DeleteVehicleInBay(coords)
    local vehicles = GetGamePool('CVehicle')

    for _, vehicle in ipairs(vehicles) do
        if DoesEntityExist(vehicle) and #(GetEntityCoords(vehicle) - coords) < Config.OccupiedCheckRadius then
            local driverPed      = GetPedInVehicleSeat(vehicle, -1)
            local passengerCount = GetVehicleNumberOfPassengers(vehicle)

            -- Only proceed if vehicle is unoccupied or owned by the local player
            if NetworkGetEntityOwner(vehicle) == PlayerId() or (driverPed == 0 and passengerCount == 0) then
                -- Request network control before issuing deletion
                if not NetworkHasControlOfEntity(vehicle) then
                    NetworkRequestControlOfEntity(vehicle)
                    local timeout = GetGameTimer() + 500
                    while not NetworkHasControlOfEntity(vehicle) and GetGameTimer() < timeout do
                        Wait(10)
                    end
                end

                SetEntityAsMissionEntity(vehicle, true, true)
                DeleteVehicle(vehicle)

                -- Fallback deletion native if entity persists
                if DoesEntityExist(vehicle) then
                    DeleteEntity(vehicle)
                end

                return true
            end
        end
    end

    return false
end

-- ============================================================
-- VEHICLE CREATION & STREAMING
-- ============================================================

--- Safely streams the vehicle model, instantiates the entity, places it on the ground,
--- starts the engine, and warps the player into the driver's seat.
---
---@param model   string|number  Vehicle spawn model name or joaat hash
---@param coords  vector3        World coordinates for spawning
---@param heading number         Heading in degrees (0.0–360.0)
local function SpawnVehicle(model, coords, heading)
    -- Hide active interaction text UI immediately upon spawning
    lib.hideTextUI()

    -- Resolve model hash
    local hash = type(model) == 'string' and joaat(model) or model

    -- Verify that the model exists in the game streaming archive
    if not IsModelInCdimage(hash) then
        lib.notify({
            title       = 'Invalid Model',
            description = 'Vehicle model does not exist in game archives',
            type        = 'error',
        })
        return
    end

    -- If enabled, clear any existing vehicle from the bay
    if Config.DeletePreviousVehicle then
        DeleteVehicleInBay(coords)
    end

    -- Verify the bay is now clear
    if IsBayOccupied(coords) then
        lib.notify({
            title       = 'Bay Occupied',
            description = 'The selected parking bay is currently occupied',
            type        = 'error',
        })
        return
    end

    -- Stream model into client memory
    RequestModel(hash)

    -- Await model loading with a 5-second timeout to prevent thread deadlock
    local timeout = GetGameTimer() + 5000
    while not HasModelLoaded(hash) do
        if GetGameTimer() > timeout then
            lib.notify({
                title       = 'Streaming Timeout',
                description = 'Vehicle model took too long to load',
                type        = 'error',
            })
            return
        end
        Wait(10)
    end

    -- Instantiate the vehicle in the game world
    local vehicle = CreateVehicle(hash, coords.x, coords.y, coords.z, heading, true, false)

    -- Release the streaming asset handle now that entity exists
    SetModelAsNoLongerNeeded(hash)

    if vehicle and DoesEntityExist(vehicle) then
        -- Position the vehicle properly upon the ground surface before ped interaction
        SetVehicleOnGroundProperly(vehicle)

        -- Warp the local player ped into the driver's seat (-1)
        TaskWarpPedIntoVehicle(PlayerPedId(), vehicle, -1)

        -- Switch on the engine immediately
        SetVehicleEngineOn(vehicle, true, true, false)

        lib.notify({
            title       = 'Vehicle Spawned',
            description = ('%s is ready for departure'):format(GetDisplayNameFromVehicleModel(hash)),
            type        = 'success',
        })
    end
end

-- ============================================================
-- NETWORK EVENT DISPATCHERS
-- ============================================================

--- Handles server-approved vehicle spawn instructions.
--- CRITICAL: Wraps SpawnVehicle inside a CreateThread coroutine to ensure
--- that streaming Wait() calls do not trigger engine C-call yield crashes.
RegisterNetEvent('VehicleSpawnArea:doSpawn', function(model, coords, heading)
    local spawnCoords = type(coords) == 'vector3' and coords or vector3(coords.x, coords.y, coords.z)
    local spawnHeading = tonumber(heading) or 0.0

    CreateThread(function()
        SpawnVehicle(model, spawnCoords, spawnHeading)
    end)
end)

--- Displays standard server notifications using ox_lib.
RegisterNetEvent('VehicleSpawnArea:notify', function(data)
    lib.notify(data)
end)

-- ============================================================
-- CONTEXT MENUS (ox_lib)
-- ============================================================

--- Displays the primary vehicle selection menu for a garage location.
---
---@param locationId string  Key matching Config.Locations
---@param location   table   Location configuration table
OpenVehicleMenu = function(locationId, location)
    local options = {}

    for vehIdx, vehicle in ipairs(location.vehicles) do
        if CanSpawnVehicle(location, vehicle) then
            local capturedIdx     = vehIdx
            local capturedVehicle = vehicle

            table.insert(options, {
                title       = capturedVehicle.label,
                description = 'Select an available parking bay for this vehicle',
                icon        = 'car',
                onSelect    = function()
                    OpenBaySelectionMenu(locationId, location, capturedIdx, capturedVehicle)
                end,
            })
        end
    end

    -- If no vehicles passed permission checks, notify the player
    if #options == 0 then
        lib.notify({
            title       = 'Authorisation Denied',
            description = 'You do not possess permission to spawn vehicles at this location',
            type        = 'error',
        })
        return
    end

    -- Hide any floating text prompt whilst viewing the menu
    lib.hideTextUI()

    lib.registerContext({
        id      = 'vsa_menu_' .. locationId,
        title   = location.label .. ' — Vehicles',
        options = options,
    })
    lib.showContext('vsa_menu_' .. locationId)
end

--- Displays the parking bay selection submenu for a chosen vehicle.
---
---@param locationId string  Key matching Config.Locations
---@param location   table   Location configuration table
---@param vehIdx     number  Vehicle index within location.vehicles
---@param vehicle    table   Vehicle configuration table
OpenBaySelectionMenu = function(locationId, location, vehIdx, vehicle)
    local options = {}

    for bayIdx, bay in ipairs(location.bays) do
        local occupied = IsBayOccupied(bay.coords)
        local canUse   = not occupied or Config.DeletePreviousVehicle
        local capturedBayIdx = bayIdx

        table.insert(options, {
            title       = bay.label,
            description = occupied
                and (Config.DeletePreviousVehicle and '⚠️ Occupied — will replace existing vehicle' or '🚗 Occupied — unavailable')
                or  '🅿️ Available for spawn',
            icon        = occupied and 'car' or 'square-parking',
            disabled    = not canUse,
            onSelect    = canUse and function()
                -- Dispatch request to server for authoritative validation
                TriggerServerEvent('VehicleSpawnArea:requestSpawn', locationId, vehIdx, capturedBayIdx)
            end or nil,
        })
    end

    lib.registerContext({
        id      = 'vsa_bay_select_' .. locationId,
        title   = vehicle.label .. ' — Select Bay',
        menu    = 'vsa_menu_' .. locationId,    -- Returns to vehicle menu on back action
        options = options,
    })
    lib.showContext('vsa_bay_select_' .. locationId)
end

--- Displays the direct vehicle menu when interacting directly at an individual bay.
---
---@param locationId string  Key matching Config.Locations
---@param location   table   Location configuration table
---@param bay        table   Bay configuration table
---@param bayIdx     number  Bay index within location.bays
OpenBayDirectMenu = function(locationId, location, bay, bayIdx)
    local occupied = IsBayOccupied(bay.coords)

    -- If bay is occupied and replacement is disabled, prevent menu display
    if occupied and not Config.DeletePreviousVehicle then
        lib.notify({
            title       = 'Bay In Use',
            description = 'This parking bay is currently occupied',
            type        = 'error',
        })
        return
    end

    local options = {}

    for vehIdx, vehicle in ipairs(location.vehicles) do
        if CanSpawnVehicle(location, vehicle) then
            local capturedIdx = vehIdx

            table.insert(options, {
                title       = vehicle.label,
                description = occupied
                    and ('Spawn in %s (will replace occupying vehicle)'):format(bay.label)
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
            title       = 'Authorisation Denied',
            description = 'You do not possess permission to spawn vehicles at this location',
            type        = 'error',
        })
        return
    end

    lib.hideTextUI()

    lib.registerContext({
        id      = 'vsa_bay_direct_' .. locationId .. '_' .. bayIdx,
        title   = ('%s — %s'):format(location.label, bay.label),
        options = options,
    })
    lib.showContext('vsa_bay_direct_' .. locationId .. '_' .. bayIdx)
end

-- ============================================================
-- DISTANCE-GATED MARKER RENDERING
-- ============================================================
-- Renders 3D world markers with dynamic distance throttling.
-- Sleeps for 500 ms when outside 80 metres to eliminate CPU/GPU overhead.

CreateThread(function()
    while true do
        local sleep        = 500
        local playerCoords = GetEntityCoords(PlayerPedId())

        for _, location in pairs(Config.Locations) do
            -- Only render markers if the player has permission to access the location
            if HasPermission(location) then
                local menuPoint  = location.menuPoint
                local distToMenu = #(playerCoords - menuPoint.coords)

                -- Activate frame-by-frame rendering when within 80 metres
                if distToMenu < 80.0 then
                    sleep = 0

                    -- ----------------------------------------
                    -- Central Interaction Marker
                    -- ----------------------------------------
                    if distToMenu < menuPoint.marker.drawDistance then
                        local col = GetMarkerColour(menuPoint.marker)
                        DrawMarker(
                            menuPoint.marker.type,
                            menuPoint.coords.x,
                            menuPoint.coords.y,
                            menuPoint.coords.z - 0.5,
                            0.0, 0.0, 0.0,
                            0.0, 0.0, 0.0,
                            menuPoint.marker.scale,
                            menuPoint.marker.scale,
                            menuPoint.marker.scale,
                            col.r, col.g, col.b,
                            200,
                            false, true, 2, nil, nil, false
                        )
                    end

                    -- ----------------------------------------
                    -- Parking Bay Markers (Occupancy Colouring)
                    -- ----------------------------------------
                    for _, bay in ipairs(location.bays) do
                        if #(playerCoords - bay.coords) < 25.0 then
                            local isOccupied = IsBayOccupied(bay.coords)
                            local baseColour = GetMarkerColour(bay.marker)

                            DrawMarker(
                                bay.marker.type,
                                bay.coords.x,
                                bay.coords.y,
                                bay.coords.z,
                                0.0, 0.0, 0.0,
                                0.0, 0.0, 0.0,
                                bay.marker.scale,
                                bay.marker.scale,
                                bay.marker.scale,
                                -- Red (255, 0, 0) when occupied; configured colour when free
                                isOccupied and 255 or baseColour.r,
                                isOccupied and 0   or baseColour.g,
                                isOccupied and 0   or baseColour.b,
                                200,
                                false, true, 2, nil, nil, false
                            )
                        end
                    end
                end
            end
        end

        Wait(sleep)
    end
end)

-- ============================================================
-- ZONE REGISTRATION (ox_lib)
-- ============================================================
-- Registers sphere interaction zones for menu points and bays.
-- Manages currentZone state for zero-overhead input handling.

CreateThread(function()
    -- Short delay to ensure framework exports are fully initialised
    Wait(500)

    for locationId, location in pairs(Config.Locations) do

        -- ----------------------------------------------------
        -- Central Interaction Point Zone
        -- ----------------------------------------------------
        local menuZone = lib.zones.sphere({
            coords  = location.menuPoint.coords,
            radius  = location.menuPoint.radius,
            onEnter = function()
                if HasPermission(location) then
                    currentZone = {
                        type       = 'menu',
                        locationId = locationId,
                        location   = location,
                    }
                    lib.showTextUI(
                        '[E] ' .. location.label,
                        { position = 'left-center', icon = 'warehouse' }
                    )
                end
            end,
            onExit  = function()
                if currentZone and currentZone.type == 'menu' and currentZone.locationId == locationId then
                    currentZone = nil
                end
                lib.hideTextUI()
            end,
        })
        table.insert(activeZones, menuZone)

        -- ----------------------------------------------------
        -- Individual Parking Bay Zones
        -- ----------------------------------------------------
        for bayIdx, bay in ipairs(location.bays) do
            local capturedBayIdx = bayIdx

            local bayZone = lib.zones.sphere({
                coords  = bay.coords,
                radius  = 2.5,
                onEnter = function()
                    if HasPermission(location) then
                        currentZone = {
                            type       = 'bay',
                            locationId = locationId,
                            location   = location,
                            bay        = bay,
                            bayIdx     = capturedBayIdx,
                        }
                        lib.showTextUI(
                            ('[E] %s — %s'):format(location.label, bay.label),
                            { position = 'left-center', icon = 'square-parking' }
                        )
                    end
                end,
                onExit  = function()
                    if currentZone and currentZone.type == 'bay'
                    and currentZone.locationId == locationId
                    and currentZone.bayIdx == capturedBayIdx then
                        currentZone = nil
                    end
                    lib.hideTextUI()
                end,
            })
            table.insert(activeZones, bayZone)
        end
    end
end)

-- ============================================================
-- INPUT CONTROL LISTENER
-- ============================================================
-- Listens for the [E] interaction key (Control 38).
-- Uses tracked currentZone state instead of scanning all world coordinates.

CreateThread(function()
    while true do
        Wait(0)

        if IsControlJustReleased(0, 38) then    -- Control 38 corresponds to the 'E' key
            if currentZone then
                -- Do not open if the player is currently sitting in a vehicle
                local playerPed = PlayerPedId()
                if not IsPedInAnyVehicle(playerPed, false) then
                    if currentZone.type == 'menu' then
                        OpenVehicleMenu(currentZone.locationId, currentZone.location)
                    elseif currentZone.type == 'bay' then
                        OpenBayDirectMenu(currentZone.locationId, currentZone.location, currentZone.bay, currentZone.bayIdx)
                    end
                end
            end
        end
    end
end)

-- ============================================================
-- RESOURCE TEARDOWN & RESTART CLEANUP
-- ============================================================

--- Cleans up registered ox_lib zones and active UI prompts when the resource stops.
--- Prevents duplicate zones, memory leaks, and lingering UI on server restarts.
AddEventHandler('onResourceStop', function(resourceName)
    if GetCurrentResourceName() ~= resourceName then return end

    -- Hide any open text prompt
    lib.hideTextUI()

    -- Remove all registered ox_lib zones
    for _, zone in ipairs(activeZones) do
        if zone and zone.remove then
            zone:remove()
        end
    end
    activeZones = {}
    currentZone = nil
end)
