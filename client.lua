-- ========== MARKER DRAWING ==========
CreateThread(function()
    while true do
        Wait(0)
        local playerCoords = GetEntityCoords(PlayerPedId())
        
        -- Draw central marker
        if #(playerCoords - Config.MenuLocation.coords) < Config.MenuLocation.marker.drawDistance then
            DrawMarker(
                Config.MenuLocation.marker.type,
                Config.MenuLocation.coords.x, 
                Config.MenuLocation.coords.y, 
                Config.MenuLocation.coords.z - 0.5,
                0.0, 0.0, 0.0,
                0.0, 0.0, 0.0,
                Config.MenuLocation.marker.scale,
                Config.MenuLocation.marker.scale,
                Config.MenuLocation.marker.scale,
                Config.MenuLocation.marker.color.r,
                Config.MenuLocation.marker.color.g,
                Config.MenuLocation.marker.color.b,
                200,
                false, true, 2, nil, nil, false
            )
        end

        -- Draw bay markers (color changes based on occupancy)
        for _, bay in ipairs(Config.ParkingBays) do
            if #(playerCoords - bay.coords) < 25.0 then
                local isOccupied = isBayOccupied(bay.coords)
                DrawMarker(
                    bay.marker.type,
                    bay.coords.x, bay.coords.y, bay.coords.z,
                    0.0, 0.0, 0.0,
                    0.0, 0.0, 0.0,
                    bay.marker.scale,
                    bay.marker.scale,
                    bay.marker.scale,
                    isOccupied and 255 or bay.marker.color.r,  -- Red if occupied
                    isOccupied and 0 or bay.marker.color.g,
                    isOccupied and 0 or bay.marker.color.b,
                    200,
                    false, true, 2, nil, nil, false
                )
            end
        end
    end
end)

-- ========== CORE FUNCTIONALITY ==========
local currentBay = nil

-- Check bay occupancy
function isBayOccupied(coords)
    local vehicles = GetGamePool('CVehicle')
    for _, vehicle in ipairs(vehicles) do
        if #(GetEntityCoords(vehicle) - coords) < Config.OccupiedCheckRadius then
            return true
        end
    end
    return false
end

-- Central zone interaction
lib.zones.sphere({
    coords = Config.MenuLocation.coords,
    radius = Config.MenuLocation.radius,
    onEnter = function()
        lib.showTextUI('[E] Vehicle Spawn Menu', { position = "left-center" })
    end,
    onExit = function()
        lib.hideTextUI()
    end
})

-- Bay zone interactions
for _, bay in ipairs(Config.ParkingBays) do
    lib.zones.sphere({
        coords = bay.coords,
        radius = 2.5,
        onEnter = function()
            currentBay = bay
            lib.showTextUI(('[E] Spawn Vehicle (Bay %s)'):format(bay.id), { position = "left-center" })
        end,
        onExit = function()
            currentBay = nil
            lib.hideTextUI()
        end
    })
end

-- Key controls
CreateThread(function()
    while true do
        Wait(0)
        if IsControlJustReleased(0, 38) then -- E key
            -- Central menu
            if #(GetEntityCoords(PlayerPedId()) - Config.MenuLocation.coords) < Config.MenuLocation.radius then
                openVehicleMenu()
            -- Bay-specific menu
            elseif currentBay then
                openBaySpecificMenu(currentBay)
            end
        end
    end
end)

-- ========== MENU SYSTEMS ==========
function openVehicleMenu()
    local options = {}
    
    for _, vehicle in ipairs(Config.Vehicles) do
        table.insert(options, {
            title = vehicle.label,
            description = 'Select bay for '..vehicle.label,
            onSelect = function()
                selectBayForVehicle(vehicle.model)
            end
        })
    end

    lib.registerContext({
        id = 'central_vehicle_menu',
        title = 'Vehicle Selection',
        menu = 'main',
        options = options
    })
    lib.showContext('central_vehicle_menu')
end

function selectBayForVehicle(model)
    local options = {}
    
    for _, bay in ipairs(Config.ParkingBays) do
        local occupied = isBayOccupied(bay.coords)
        table.insert(options, {
            title = bay.label,
            description = occupied and '🚗 Occupied' or '🅿️ Available',
            disabled = occupied,
            onSelect = not occupied and function()
                spawnVehicle(model, bay.coords, bay.heading)
            end or nil
        })
    end

    lib.registerContext({
        id = 'bay_selection_menu',
        title = 'Select Parking Bay',
        menu = 'central_vehicle_menu',
        options = options
    })
    lib.showContext('bay_selection_menu')
end

function openBaySpecificMenu(bay)
    if isBayOccupied(bay.coords) then
        lib.notify({ title = 'Bay Occupied', description = 'This bay is currently in use', type = 'error' })
        return
    end

    local options = {}
    
    for _, vehicle in ipairs(Config.Vehicles) do
        table.insert(options, {
            title = vehicle.label,
            description = 'Spawn in Bay '..bay.id,
            onSelect = function()
                spawnVehicle(vehicle.model, bay.coords, bay.heading)
            end
        })
    end

    lib.registerContext({
        id = 'bay_vehicle_menu',
        title = 'Bay '..bay.id..' - Vehicle Select',
        menu = 'main',
        options = options
    })
    lib.showContext('bay_vehicle_menu')
end

-- ========== VEHICLE SPAWNING ==========
function spawnVehicle(model, coords, heading)
    -- Final occupancy check
    if isBayOccupied(coords) then
        lib.notify({ title = 'Error', description = 'Bay was just occupied!', type = 'error' })
        return
    end

    -- Load model
    if not IsModelInCdimage(model) then
        lib.notify({ title = 'Error', description = 'Invalid vehicle model', type = 'error' })
        return
    end

    RequestModel(model)
    while not HasModelLoaded(model) do
        Wait(10)
    end

    -- Create vehicle
    local vehicle = CreateVehicle(model, coords.x, coords.y, coords.z, heading, true, false)
    TaskWarpPedIntoVehicle(PlayerPedId(), vehicle, -1)
    SetVehicleEngineOn(vehicle, true, true, false)
    
    lib.notify({ 
        title = 'Success', 
        description = ('%s spawned in bay'):format(GetDisplayNameFromVehicleModel(model)), 
        type = 'success' 
    })
end

-- Server event handlers
RegisterNetEvent('vehicleSpawn:clientSpawn', spawnVehicle)