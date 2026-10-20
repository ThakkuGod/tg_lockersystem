fx_version 'cerulean'
game 'gta5'
lua54 'yes'
author 'TG'
description 'Multi-framework rental lockers'
version '1.0.0'

shared_scripts { '@ox_lib/init.lua', 'config.lua' }
client_script 'client/main.lua'
server_scripts { '@oxmysql/lib/MySQL.lua', 'server/bridge.lua', 'server/main.lua' }
dependencies { 'ox_lib', 'ox_target', 'ox_inventory', 'oxmysql', '/onesync' }
