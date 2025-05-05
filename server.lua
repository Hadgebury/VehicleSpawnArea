RegisterNetEvent('vehicleSpawn:requestMenu', function()
    TriggerClientEvent('vehicleSpawn:openMenu', source)
end)

RegisterNetEvent('vehicleSpawn:spawnVehicle', function(model, coords, heading)
    -- Add any server-side checks here (anti-spam, permissions, etc.)
    TriggerClientEvent('vehicleSpawn:clientSpawn', source, model, coords, heading)
end)