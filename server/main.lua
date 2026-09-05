--[[
╔══════════════════════════════════════════════════════════════════╗
║                  VehicleSpawnArea — Server                       ║
║                      server/main.lua                             ║
╠══════════════════════════════════════════════════════════════════╣
║  Handles all authoritative server-side logic:                    ║
║    • Server-authoritative ACE and job permission validation      ║
║    • Per-player anti-spam cooldown enforcement                   ║
║    • Spawn authorisation and client instruction dispatch         ║
║    • Audit logging of all vehicle spawn events                   ║
║    • Disconnection state cleanup                                 ║
║                                                                  ║
║  CRITICAL SECURITY ARCHITECTURE:                                 ║
║  Client-side checks are purely cosmetic (filtering UI items).    ║
║  All spawn requests received by the server undergo independent,  ║
║  authoritative permission and cooldown checks prior to execution.║
║                                                                  ║
║  Note: All comments and non-code text adhere to British English. ║
╚══════════════════════════════════════════════════════════════════╝
--]]

-- ============================================================
-- ANTI-SPAM & COOLDOWN STATE
-- ============================================================

--- Tracks the epoch timestamp of the last successful spawn for each player.
--- Key:   player server source ID (number)
--- Value: os.time() integer timestamp
local lastSpawnTime = {}

-- ============================================================
-- PERMISSION VALIDATION (Server-Authoritative)
-- ============================================================

--- Evaluates whether a player satisfies a single permission gate (ACE or job).
--- Operates as the authoritative counterpart to cosmetic client-side filters.
---
---@param src   number  Player server source ID
---@param perms table   Configuration table with optional fields: ace, jobs, minGrade
---@return boolean      true if the player meets the required criteria
local function CheckPermission(src, perms)
    -- If permission mode is 'none', permit all players unconditionally
    if Config.PermissionMode == 'none' then
        return true
    end

    local aceOk = false
    local jobOk = false

    -- --------------------------------------------------------
    -- 1. ACE Permission Evaluation
    -- --------------------------------------------------------
    if perms.ace then
        -- Native FiveM server function to query the principal ACE cache
        aceOk = IsPlayerAceAllowed(src, perms.ace)
    else
        -- If no ACE string is configured for this gate, ACE check passes
        aceOk = true
    end

    -- --------------------------------------------------------
    -- 2. Framework Job Evaluation
    -- --------------------------------------------------------
    if perms.jobs and #perms.jobs > 0 then
        local playerJob = Framework.GetPlayerJob(src)

        if playerJob then
            local requiredGrade = perms.minGrade or 0

            -- Compare player's job against each permitted job name and minimum grade
            for _, allowedJob in ipairs(perms.jobs) do
                if playerJob.name == allowedJob and playerJob.grade >= requiredGrade then
                    jobOk = true
                    break
                end
            end
        else
            -- If no framework job data was returned (e.g. standalone server),
            -- bypass the job check rather than locking everyone out
            if Framework.name == 'standalone' then
                jobOk = true
            end
        end
    else
        -- If no job requirements are configured for this gate, job check passes
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
        -- Logical OR: meeting either ACE OR Framework job is sufficient
        return aceOk or jobOk
    end

    return false
end

--- Applies the layered permission model to a spawn request:
---   Step 1: Location-level gate (must be satisfied to use the garage)
---   Step 2: Vehicle-level gate (evaluated only if the vehicle specifies overrides)
---
---@param src      number  Player server source ID
---@param location table   Location configuration table
---@param vehicle  table   Vehicle configuration table
---@return boolean         true if the player is authorised to spawn this vehicle
local function ValidateSpawnPermission(src, location, vehicle)
    -- Gate 1: Evaluate location-level access
    if not CheckPermission(src, location) then
        if Config.Debug then
            print(('[VehicleSpawnArea] Player "%s" (ID: %s) FAILED location permission for "%s"'):format(
                GetPlayerName(src) or 'Unknown', src, location.label
            ))
        end
        return false
    end

    -- Gate 2: Evaluate vehicle-level access (only if overrides are configured)
    if vehicle.ace or (vehicle.jobs and #vehicle.jobs > 0) then
        if not CheckPermission(src, vehicle) then
            if Config.Debug then
                print(('[VehicleSpawnArea] Player "%s" (ID: %s) FAILED vehicle permission for "%s"'):format(
                    GetPlayerName(src) or 'Unknown', src, vehicle.label
                ))
            end
            return false
        end
    end

    return true
end

-- ============================================================
-- NETWORK EVENT: SPAWN REQUEST
-- ============================================================

--- Receives a vehicle spawn request from a client, performs complete authoritative
--- validation, and dispatches the creation command back to the authorised client.
---
--- Event Arguments:
---   locationId (string) — Key matching Config.Locations
---   vehIdx     (number) — Integer index of vehicle in location.vehicles
---   bayIdx     (number) — Integer index of bay in location.bays
RegisterNetEvent('VehicleSpawnArea:requestSpawn', function(locationId, vehIdx, bayIdx)
    -- Localise source immediately at the top of the event to ensure thread-safety
    local src = source

    -- --------------------------------------------------------
    -- Sanity & Security Checks
    -- --------------------------------------------------------
    if type(locationId) ~= 'string' then
        print(('[VehicleSpawnArea] WARNING: Player "%s" (ID: %s) sent non-string locationId'):format(
            GetPlayerName(src) or 'Unknown', src
        ))
        return
    end

    local location = Config.Locations[locationId]
    if not location then
        print(('[VehicleSpawnArea] WARNING: Player "%s" (ID: %s) requested invalid location "%s"'):format(
            GetPlayerName(src) or 'Unknown', src, tostring(locationId)
        ))
        return
    end

    -- Convert indices to numbers to guard against string payloads
    local numVehIdx = tonumber(vehIdx)
    local numBayIdx = tonumber(bayIdx)

    if not numVehIdx or not numBayIdx then
        print(('[VehicleSpawnArea] WARNING: Player "%s" (ID: %s) sent malformed indices'):format(
            GetPlayerName(src) or 'Unknown', src
        ))
        return
    end

    local vehicle = location.vehicles and location.vehicles[numVehIdx]
    if not vehicle then
        print(('[VehicleSpawnArea] WARNING: Player "%s" (ID: %s) requested non-existent vehicle index %s'):format(
            GetPlayerName(src) or 'Unknown', src, tostring(vehIdx)
        ))
        return
    end

    local bay = location.bays and location.bays[numBayIdx]
    if not bay then
        print(('[VehicleSpawnArea] WARNING: Player "%s" (ID: %s) requested non-existent bay index %s'):format(
            GetPlayerName(src) or 'Unknown', src, tostring(bayIdx)
        ))
        return
    end

    -- --------------------------------------------------------
    -- Anti-Spam Cooldown Verification
    -- --------------------------------------------------------
    local now = os.time()
    local lastSpawn = lastSpawnTime[src]

    if lastSpawn and (now - lastSpawn) < Config.SpawnCooldown then
        local remaining = Config.SpawnCooldown - (now - lastSpawn)
        TriggerClientEvent('VehicleSpawnArea:notify', src, {
            title       = 'Cooldown Active',
            description = ('Please wait %d second%s before requesting another vehicle'):format(
                remaining, remaining == 1 and '' or 's'
            ),
            type        = 'error',
        })
        return
    end

    -- --------------------------------------------------------
    -- Authoritative Permission Verification
    -- --------------------------------------------------------
    if not ValidateSpawnPermission(src, location, vehicle) then
        TriggerClientEvent('VehicleSpawnArea:notify', src, {
            title       = 'Authorisation Denied',
            description = 'You are not authorised to spawn this vehicle',
            type        = 'error',
        })
        return
    end

    -- --------------------------------------------------------
    -- Authorisation Approved: Record & Dispatch
    -- --------------------------------------------------------
    lastSpawnTime[src] = now

    -- Audit log output to server console
    print(('[VehicleSpawnArea] Player "%s" (ID: %s) spawned "%s" at "%s" (%s)'):format(
        GetPlayerName(src) or 'Unknown',
        src,
        vehicle.label,
        location.label,
        bay.label
    ))

    -- Send spawn instruction solely to the requesting client.
    -- Coordinates are transmitted as a numeric table to ensure cross-framework serialisation safety.
    TriggerClientEvent('VehicleSpawnArea:doSpawn', src,
        vehicle.model,
        { x = bay.coords.x, y = bay.coords.y, z = bay.coords.z },
        bay.heading
    )
end)

-- ============================================================
-- DISCONNECTION CLEANUP
-- ============================================================

--- Removes a player's cooldown entry upon disconnection to prevent memory leaks.
AddEventHandler('playerDropped', function()
    local src = source
    if src then
        lastSpawnTime[src] = nil
    end
end)

-- ============================================================
-- STARTUP DIAGNOSTICS & SUMMARY
-- ============================================================

--- Outputs an operational summary to the server console upon resource launch.
CreateThread(function()
    local locationCount = 0
    local vehicleCount  = 0

    for _, location in pairs(Config.Locations) do
        locationCount = locationCount + 1
        if location.vehicles then
            vehicleCount = vehicleCount + #location.vehicles
        end
    end

    print(('[VehicleSpawnArea] Initialised — %d location(s), %d vehicle(s) | Active Framework: %s | Permission Mode: %s'):format(
        locationCount,
        vehicleCount,
        Framework.name,
        Config.PermissionMode
    ))
end)
