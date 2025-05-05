fx_version 'cerulean'
game 'gta5'
author 'Hadgebury'
description 'Vehicle Spawn Area script using ox_lib'

-- Enable Lua 5.4 (required for ox_lib)
lua54 'yes'

shared_script '@ox_lib/init.lua'

client_scripts {
    'config.lua',
    'client.lua'
}

server_scripts {
    'config.lua',
    'server.lua'
}

dependencies {
    'ox_lib'
}
