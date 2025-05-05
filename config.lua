Config = {}

-- Vehicle options
Config.Vehicles = {
    { label = '2020 Mondeo Dog Section', model = 'BX21AWW' },
    { label = 'Ambulance', model = 'LX69AXC' },
}

-- Central interaction point
Config.MenuLocation = {
    coords = vector3(425.41, -1015.89, 29.01),
    radius = 3.0,
    marker = {
        type = 20,                  -- Vertical rotating cylinder
        scale = 1.5,                -- Size
        color = { r = 0, g = 200, b = 255 },  -- Bright blue
        drawDistance = 15.0
    }
}

-- Parking bays
Config.ParkingBays = {
    {
        id = 1,
        label = "Bay 1",
        coords = vector3(426.77, -1028.15, 29),
        heading = 5.51,
        marker = { 
            type = 36,              -- Garage symbol
            scale = 1.5, 
            color = { r = 0, g = 255, b = 0 }  -- Green when available
        }
    },
    {
        id = 2,
        label = "Bay 2",
        coords = vector3(430.88, -1027.11, 28.93),
        heading = 5.02,
        marker = { 
            type = 36, 
            scale = 1.5, 
            color = { r = 0, g = 255, b = 0 } 
        }
    }
}

-- Settings
Config.OccupiedCheckRadius = 3.0  -- Distance to check for existing vehicles