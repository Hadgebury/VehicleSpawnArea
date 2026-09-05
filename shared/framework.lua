--[[
╔══════════════════════════════════════════════════════════════════╗
║                 VehicleSpawnArea — Framework                     ║
║                    shared/framework.lua                          ║
╠══════════════════════════════════════════════════════════════════╣
║  Auto-detects the active framework and provides a unified,       ║
║  crash-resilient API for retrieving player job and grade data     ║
║  across both client and server environments.                     ║
║                                                                  ║
║  Detection hierarchy (first active framework takes precedence):  ║
║    1. QBox       — qbx_core                                      ║
║    2. QBCore     — qb-core                                       ║
║    3. ESX        — es_extended                                   ║
║    4. Standalone — fallback when no framework is present         ║
║                                                                  ║
║  Note: All non-code text and comments adhere to British English. ║
╚══════════════════════════════════════════════════════════════════╝
--]]

--- Global framework interface table.
--- Exposes the detected framework identifier and unified job getter.
Framework      = {}
Framework.name = 'standalone'

-- Cached reference to the framework's core object (ESX / QBCore).
local cachedObj = nil

-- ============================================================
-- FRAMEWORK AUTO-DETECTION
-- ============================================================

--- Evaluates running resources to establish the active framework.
--- Can be executed at startup and lazily re-evaluated if initially standalone.
local function DetectFramework()
    -- Check for QBox first, as it maintains compatibility layers with QBCore
    if GetResourceState('qbx_core') == 'started' then
        Framework.name = 'qbox'
    -- Check for standard QBCore
    elseif GetResourceState('qb-core') == 'started' then
        Framework.name = 'qbcore'
    -- Check for ESX Legacy / Extended
    elseif GetResourceState('es_extended') == 'started' then
        Framework.name = 'esx'
    -- Standalone fallback
    else
        Framework.name = 'standalone'
    end

    -- Output detection diagnostics if debug logging is enabled
    if Config and Config.Debug then
        print(('[VehicleSpawnArea] Framework detected: %s'):format(Framework.name))
    end
end

-- Perform initial detection immediately upon script execution
DetectFramework()

--- Ensures the framework has been detected. If previously marked as standalone
--- (for example, if this resource started before the framework), re-checks status.
local function EnsureFramework()
    if Framework.name == 'standalone' then
        DetectFramework()
    end
end

-- ============================================================
-- FRAMEWORK OBJECT RETRIEVAL & CACHING
-- ============================================================

--- Retrieves and caches the framework's primary object or export reference.
--- Reuses the cached handle on subsequent calls to avoid redundant export lookups.
---
---@return table|nil  The core framework object, or nil in standalone mode
local function GetFrameworkObject()
    if cachedObj then
        return cachedObj
    end

    EnsureFramework()

    if Framework.name == 'esx' then
        -- ESX exports its shared object through es_extended
        local ok, exportObj = pcall(function()
            return exports['es_extended']:getSharedObject()
        end)
        if ok and exportObj then
            cachedObj = exportObj
        end
    elseif Framework.name == 'qbcore' then
        -- QBCore exports its core object through qb-core
        local ok, exportObj = pcall(function()
            return exports['qb-core']:GetCoreObject()
        end)
        if ok and exportObj then
            cachedObj = exportObj
        end
    elseif Framework.name == 'qbox' then
        -- QBox uses modular exports; store the core export handle
        cachedObj = exports['qbx_core']
    end

    return cachedObj
end

-- ============================================================
-- GRADE NORMALISATION HELPER
-- ============================================================

--- Safely extracts a numeric grade from framework job grade data.
--- Guards against crashes where grade is an integer rather than a table
--- (preventing "attempt to index a number value (field 'level')" errors).
---
---@param gradeData table|number|nil  The raw grade data returned by the framework
---@return number                     The normalised numeric grade level
local function NormaliseGrade(gradeData)
    if type(gradeData) == 'table' then
        return tonumber(gradeData.level) or 0
    elseif type(gradeData) == 'number' then
        return math.floor(gradeData)
    end
    return 0
end

-- ============================================================
-- CLIENT-SIDE: GetPlayerJob
-- ============================================================
-- Only compiled and registered in the client environment.

if not IsDuplicityVersion() then

    --- Retrieves the local player's current job name and grade.
    --- Automatically adapts to ESX, QBCore, and QBox client data structures.
    ---
    ---@return table|nil  Table containing { name = string, grade = number }, or nil
    function Framework.GetPlayerJob()
        EnsureFramework()

        -- ----------------------------------------------------
        -- ESX Client Job Extraction
        -- ----------------------------------------------------
        if Framework.name == 'esx' then
            local obj = GetFrameworkObject()
            if not obj then return nil end

            local playerData = obj.GetPlayerData and obj.GetPlayerData()
            if playerData and playerData.job then
                return {
                    name  = playerData.job.name,
                    grade = NormaliseGrade(playerData.job.grade),
                }
            end

        -- ----------------------------------------------------
        -- QBCore Client Job Extraction
        -- ----------------------------------------------------
        elseif Framework.name == 'qbcore' then
            local obj = GetFrameworkObject()
            if not obj or not obj.Functions then return nil end

            local playerData = obj.Functions.GetPlayerData()
            if playerData and playerData.job then
                return {
                    name  = playerData.job.name,
                    grade = NormaliseGrade(playerData.job.grade),
                }
            end

        -- ----------------------------------------------------
        -- QBox Client Job Extraction
        -- ----------------------------------------------------
        elseif Framework.name == 'qbox' then
            local ok, playerData = pcall(function()
                return exports['qbx_core']:GetPlayerData()
            end)

            if ok and playerData and playerData.job then
                return {
                    name  = playerData.job.name,
                    grade = NormaliseGrade(playerData.job.grade),
                }
            end

        -- ----------------------------------------------------
        -- Standalone Mode (No Framework)
        -- ----------------------------------------------------
        else
            return nil
        end

        return nil
    end

end

-- ============================================================
-- SERVER-SIDE: GetPlayerJob
-- ============================================================
-- Only compiled and registered in the server environment.

if IsDuplicityVersion() then

    --- Retrieves a specific connected player's job name and grade by server ID.
    --- Provides authoritative validation for server-side permission checks.
    ---
    ---@param source number  The player's server source ID
    ---@return table|nil     Table containing { name = string, grade = number }, or nil
    function Framework.GetPlayerJob(source)
        EnsureFramework()

        local src = tonumber(source)
        if not src then return nil end

        -- ----------------------------------------------------
        -- ESX Server Job Extraction
        -- ----------------------------------------------------
        if Framework.name == 'esx' then
            local obj = GetFrameworkObject()
            if not obj then return nil end

            local xPlayer = obj.GetPlayerFromId(src)
            if xPlayer then
                -- Accommodate both xPlayer.getJob() and direct xPlayer.job property
                local job = (xPlayer.getJob and xPlayer.getJob()) or xPlayer.job
                if job then
                    return {
                        name  = job.name,
                        grade = NormaliseGrade(job.grade),
                    }
                end
            end

        -- ----------------------------------------------------
        -- QBCore Server Job Extraction
        -- ----------------------------------------------------
        elseif Framework.name == 'qbcore' then
            local obj = GetFrameworkObject()
            if not obj or not obj.Functions then return nil end

            local player = obj.Functions.GetPlayer(src)
            if player and player.PlayerData and player.PlayerData.job then
                return {
                    name  = player.PlayerData.job.name,
                    grade = NormaliseGrade(player.PlayerData.job.grade),
                }
            end

        -- ----------------------------------------------------
        -- QBox Server Job Extraction
        -- ----------------------------------------------------
        elseif Framework.name == 'qbox' then
            local ok, player = pcall(function()
                return exports['qbx_core']:GetPlayer(src)
            end)

            if ok and player and player.PlayerData and player.PlayerData.job then
                return {
                    name  = player.PlayerData.job.name,
                    grade = NormaliseGrade(player.PlayerData.job.grade),
                }
            end

        -- ----------------------------------------------------
        -- Standalone Mode (No Framework)
        -- ----------------------------------------------------
        else
            return nil
        end

        return nil
    end

end
