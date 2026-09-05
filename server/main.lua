--[[
╔══════════════════════════════════════════════════════════════════╗
║                  VehicleSpawnArea — Server                       ║
║                      server/main.lua                             ║
╠══════════════════════════════════════════════════════════════════╣
║  Handles all server-side logic:                                  ║
║    • Authoritative ACE + job permission validation               ║
║    • Anti-spam cooldown enforcement per player                   ║
║    • Spawn authorisation → triggers client to create the vehicle ║
║    • Console logging of all spawns                               ║
║    • Cleanup of player state on disconnect                       ║
║                                                                  ║
║  All permission checks here are AUTHORITATIVE. Even if a client  ║
║  bypasses the client-side menu filters, the server will deny     ║
║  unauthorised spawn requests before any vehicle is created.      ║
╚══════════════════════════════════════════════════════════════════╝
--]]

-- ============================================================
-- ANTI-SPAM STATE
-- ============================================================

--- Tracks the last spawn timestamp for each connected player.
--- Key: player source ID (number)
--- Value: os.time() at the moment of their last successful spawn
local lastSpawnTime = {}

-- ============================================================
-- PERMISSION VALIDATION (Server-authoritative)
-- ============================================================

--- Checks whether a player passes a single permission gate (ACE or job).
--- This is the authoritative counterpart to the cosmetic client check.
---
---@param source number  Player server source ID
---@param perms  table   Config table with optional fields: ace, jobs, minGrade
---@return boolean       true if the player satisfies the permission requirements
local function CheckPermission(source, perms)
    -- 'none' mode: bypass all permission checks
    if Config.PermissionMode == 'none' then
        return true
    end

    local aceOk = false
    local jobOk = false

    -- ACE check — uses the native FiveM server-side function
    if perms.ace then
        aceOk = IsPlayerAceAllowed(source, perms.ace)
    else
        -- No ACE string defined → ACE check passes automatically
        aceOk = true
    end

    -- Job check — uses the unified Framework API from shared/framework.lua
    if perms.jobs and #perms.jobs > 0 then
        local playerJob = Framework.GetPlayerJob(source)

        if playerJob then
            -- Compare the player's job against each allowed job name and grade
            for _, allowedJob in ipairs(perms.jobs) do
                if playerJob.name == allowedJob
                and playerJob.grade >= (perms.minGrade or 0) then
                    jobOk = true
                    break
                end
            end
        else
            -- No job data returned — either standalone or the framework has no record.
            -- In standalone mode, skip the job check rather than denying everyone.
            if Framework.name == 'standalone' then
                jobOk = true
            end
        end
    else
        -- No jobs list defined → job check passes automatically
        jobOk = true
    end

    -- Evaluate the result against the configured permission mode
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

--- Applies the full layered permission model for a spawn request:
---   1. Location-level check — must pass to proceed
---   2. Vehicle-level check  — only applied if the vehicle defines its own perms
---
---@param source   number  Player server source ID
---@param location table   Location config table
---@param vehicle  table   Vehicle config table
---@return boolean         true if the player is authorised to spawn this vehicle
local function ValidateSpawnPermission(source, location, vehicle)
    -- Gate 1: location-level permission
    if not CheckPermission(source, location) then
        if Config.Debug then
            print(('[VehicleSpawnArea] Player %s (%s) FAILED location permission for "%s"'):format(
                GetPlayerName(source), source, location.label
            ))
        end
        return false
    end

    -- Gate 2: vehicle-level permission (only checked if the vehicle defines its own perms)
    if vehicle.ace or (vehicle.jobs and #vehicle.jobs > 0) then
        if not CheckPermission(source, vehicle) then
            if Config.Debug then
                print(('[VehicleSpawnArea] Player %s (%s) FAILED vehicle permission for "%s"'):format(
                    GetPlayerName(source), source, vehicle.label
                ))
            end
            return false
        end
    end

    return true
end

-- ============================================================
-- SPAWN REQUEST HANDLER
-- ============================================================

--- Receives a spawn request from the client, validates it fully,
--- and (if authorised) triggers the client to create the vehicle.
---
--- Event arguments:
---   locationId (string) — Key in Config.Locations
---   vehIdx     (number) — Index into location.vehicles
---   bayIdx     (number) — Index into location.bays
RegisterNetEvent('VehicleSpawnArea:requestSpawn', function(locationId, vehIdx, bayIdx)
    local source = source  -- Localise source immediately; the variable is not safe to use asynchronously

    -- ---- Sanity checks: ensure the indices reference valid config entries ----
    -- These protect against malformed or malicious event calls.

    local location = Config.Locations[locationId]
    if not location then
        print(('[VehicleSpawnArea] WARNING: Player %s sent invalid locationId "%s"'):format(
            GetPlayerName(source), tostring(locationId)
        ))
        return
    end

    local vehicle = location.vehicles[vehIdx]
    if not vehicle then
        print(('[VehicleSpawnArea] WARNING: Player %s sent invalid vehicle index %s for location "%s"'):format(
            GetPlayerName(source), tostring(vehIdx), locationId
        ))
        return
    end

    local bay = location.bays[bayIdx]
    if not bay then
        print(('[VehicleSpawnArea] WARNING: Player %s sent invalid bay index %s for location "%s"'):format(
            GetPlayerName(source), tostring(bayIdx), locationId
        ))
        return
    end

    -- ---- Anti-spam cooldown check ----
    local now = os.time()
    if lastSpawnTime[source] and (now - lastSpawnTime[source]) < Config.SpawnCooldown then
        local remaining = Config.SpawnCooldown - (now - lastSpawnTime[source])
        TriggerClientEvent('VehicleSpawnArea:notify', source, {
            title       = 'Cooldown',
            description = ('Please wait %d second%s before spawning again'):format(
                remaining, remaining == 1 and '' or 's'
            ),
            type        = 'error',
        })
        return
    end

    -- ---- Authoritative permission validation ----
    if not ValidateSpawnPermission(source, location, vehicle) then
        TriggerClientEvent('VehicleSpawnArea:notify', source, {
            title       = 'No Permission',
            description = 'You are not authorised to spawn this vehicle',
            type        = 'error',
        })
        return
    end

    -- ---- All checks passed — record timestamp and authorise the spawn ----
    lastSpawnTime[source] = now

    print(('[VehicleSpawnArea] %s (source: %s) spawned "%s" at "%s" — %s'):format(
        GetPlayerName(source),
        source,
        vehicle.label,
        location.label,
        bay.label
    ))

    -- Send the spawn instruction to the requesting client only.
    -- Coordinates are serialised as a plain table because vector3 is not
    -- directly network-serialisable across some framework versions.
    TriggerClientEvent('VehicleSpawnArea:doSpawn', source,
        vehicle.model,
        { x = bay.coords.x, y = bay.coords.y, z = bay.coords.z },
        bay.heading
    )
end)

-- ============================================================
-- PLAYER DROP CLEANUP
-- ============================================================

--- Clears the anti-spam entry for a player when they disconnect.
--- Prevents the lastSpawnTime table from growing indefinitely.
AddEventHandler('playerDropped', function()
    lastSpawnTime[source] = nil
end)

-- ============================================================
-- STARTUP LOG
-- ============================================================

--- Prints a summary to the console when the resource starts,
--- confirming how many locations and vehicles are loaded.
CreateThread(function()
    local locationCount = 0
    local vehicleCount  = 0

    for _, location in pairs(Config.Locations) do
        locationCount = locationCount + 1
        vehicleCount  = vehicleCount + #location.vehicles
    end

    print(('[VehicleSpawnArea] Ready — %d location(s), %d vehicle(s) | framework: %s | permission mode: %s'):format(
        locationCount,
        vehicleCount,
        Framework.name,
        Config.PermissionMode
    ))
end)
