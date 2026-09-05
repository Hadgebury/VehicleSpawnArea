fx_version 'cerulean'
game 'gta5'

author 'Hadgebury'
description 'Multi-location Vehicle Spawn Area with framework support and layered permissions'
version '2.0.0'

-- Enable Lua 5.4 (required for ox_lib)
lua54 'yes'

shared_script '@ox_lib/init.lua'

shared_scripts {
    'shared/config.lua',
    'shared/framework.lua',
}

client_scripts {
    'client/main.lua',
}

server_scripts {
    'server/main.lua',
}

dependencies {
    'ox_lib',
}
