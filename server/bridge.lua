Bridge = {}
local framework = Config.Framework
if framework == 'auto' then
    if GetResourceState('qbx_core') == 'started' then framework = 'qbox'
    elseif GetResourceState('qb-core') == 'started' then framework = 'qb'
    elseif GetResourceState('es_extended') == 'started' then framework = 'esx'
    else error('tg_lockersystem: start qbx_core, qb-core, or es_extended first') end
end
assert(framework == 'qbox' or framework == 'qb' or framework == 'esx', 'Invalid Config.Framework')
local core = framework == 'qb' and exports['qb-core']:GetCoreObject()
    or framework == 'esx' and exports.es_extended:getSharedObject()

function Bridge.player(source)
    if framework == 'qbox' then return exports.qbx_core:GetPlayer(source) end
    if framework == 'qb' then return core.Functions.GetPlayer(source) end
    return core.GetPlayerFromId(source)
end

function Bridge.identifier(player)
    if framework == 'esx' then return player.getIdentifier() end
    return player.PlayerData.citizenid
end

function Bridge.pay(player, amount)
    if framework ~= 'esx' then
        return player.Functions.RemoveMoney(Config.PaymentAccount, amount, 'locker-rental') == true
    end
    local account = Config.PaymentAccount == 'cash' and 'money' or Config.PaymentAccount
    local balance = player.getAccount(account)
    if not balance or balance.money < amount then return false end
    player.removeAccountMoney(account, amount, 'Locker rental')
    return true
end

function Bridge.refund(player, amount)
    if framework ~= 'esx' then return player.Functions.AddMoney(Config.PaymentAccount, amount, 'locker-refund') end
    player.addAccountMoney(Config.PaymentAccount == 'cash' and 'money' or Config.PaymentAccount, amount, 'Locker refund')
    return true
end
print(('tg_lockersystem: using %s'):format(framework))
