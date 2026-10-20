local LockerMail = require 'server.mail'
local ready, rentals, byStash, busy, lastRequest = false, {}, {}, {}, {}
local prefix = 'tg_locker_'
local period = Config.RentalDays * 86400000
local renewalWindow = Config.RenewalWindowDays * 86400000
local function nowMillis() return os.time() * 1000 end
assert(renewalWindow > 0, 'Renewal window must be positive')
assert(Config.PaymentAccount == 'bank' or Config.PaymentAccount == 'cash', 'Invalid payment account')
assert(period > 0 and #Config.Levels > 0, 'Invalid rental configuration')
for i, level in ipairs(Config.Levels) do
    assert(level.slots > 0 and level.weight > 0 and level.price >= 0, 'Invalid locker level')
    if i > 1 then
        assert(level.slots >= Config.Levels[i-1].slots and level.weight >= Config.Levels[i-1].weight,
            'Locker upgrades must not reduce capacity')
    end
end

local function key(owner, location) return owner .. '\0' .. location end
local function near(source, location)
    local ped = GetPlayerPed(source)
    if ped == 0 or GetPlayerRoutingBucket(source) ~= 0 then return false end
    local c = Config.Locations[location].coords
    return #(GetEntityCoords(ped) - vec3(c.x, c.y, c.z)) <= Config.AccessDistance
end
local function register(row)
    local location, level = Config.Locations[row.location], Config.Levels[row.level]
    if not location or not level then return end
    row.stash = prefix .. row.id
    byStash[row.stash] = row
    local c = location.coords
    exports.ox_inventory:RegisterStash(row.stash, location.label, level.slots, level.weight,
        false, nil, vec3(c.x, c.y, c.z))
end
local function allowed(source, row)
    if not ready or not row or row.closing or row.expires_at <= nowMillis() or not Config.Locations[row.location] then return false end
    local player = Bridge.player(source)
    return player and Bridge.identifier(player) == row.owner and near(source, row.location)
end
local function guardedInventory(source, id)
    if type(id) ~= 'string' or id:sub(1, #prefix) ~= prefix then return true end
    return allowed(source, byStash[id]) or false
end
local function installHooks()
    exports.ox_inventory:registerHook('openInventory', function(payload)
        return guardedInventory(payload.source, payload.inventoryId)
    end, { inventoryFilter = { '^tg_locker_' } })
    exports.ox_inventory:registerHook('swapItems', function(payload)
        if not guardedInventory(payload.source, payload.fromInventory)
            or not guardedInventory(payload.source, payload.toInventory) then return false end
        local function restrictedDeposit(inventory, item)
            return type(inventory) == 'string' and inventory:sub(1, #prefix) == prefix
                and type(item) == 'table' and Config.RestrictedItems[item.name] == true
        end
        -- A swap also moves the destination item back into the source inventory.
        if payload.fromInventory ~= payload.toInventory and (
            restrictedDeposit(payload.toInventory, payload.fromSlot)
            or (payload.action == 'swap' and restrictedDeposit(payload.fromInventory, payload.toSlot))
        ) then
            TriggerClientEvent('ox_lib:notify', payload.source, {
                title = 'Locker Clerk', description = 'This item cannot be stored in a locker.', type = 'error'
            })
            return false
        end
        return true
    end, { inventoryFilter = { '^tg_locker_' } })
end

-- Reject opens while rental records are loading, including after a resource restart.
installHooks()
MySQL.ready(function()
    MySQL.query.await([[CREATE TABLE IF NOT EXISTS tg_lockersystem (
        id INT UNSIGNED NOT NULL AUTO_INCREMENT,
        owner VARCHAR(100) NOT NULL,
        location VARCHAR(64) NOT NULL,
        level INT UNSIGNED NOT NULL DEFAULT 1,
        expires_at BIGINT NOT NULL,
        PRIMARY KEY (id), UNIQUE KEY owner_location (owner, location)
    )]])
    -- Convert legacy Unix seconds once; modern millisecond timestamps are already larger.
    MySQL.update.await('UPDATE tg_lockersystem SET expires_at = expires_at * 1000 WHERE expires_at > 0 AND expires_at < 100000000000')
    for _, row in ipairs(MySQL.query.await('SELECT * FROM tg_lockersystem')) do
        row.level, row.expires_at = tonumber(row.level), tonumber(row.expires_at)
        rentals[key(row.owner, row.location)] = row
        register(row)
    end
    ready = true
    LockerMail.start()
end)

AddEventHandler('onResourceStart', function(resource)
    if resource ~= 'ox_inventory' or not ready then return end
    for _, row in pairs(rentals) do register(row) end
    installHooks()
end)

local function context(source, location)
    if not ready then return nil, 'Lockers are starting. Try again shortly.' end
    if type(location) ~= 'string' or not Config.Locations[location] or not near(source, location) then
        return nil, 'You must be near the locker clerk.'
    end
    local player = Bridge.player(source)
    if not player then return nil, 'Player unavailable.' end
    return { player = player, owner = Bridge.identifier(player), location = location }
end
local function canRenew(row, now)
    if not row then return false end
    if row.expires_at > now then return row.expires_at - now <= renewalWindow end
    return true -- Expired rentals remain renewable without a deadline.
end
local function status(row)
    if not row then return { rented = false } end
    local now = nowMillis()
    return { rented = true, active = row.expires_at > now, canRenew = canRenew(row, now), level = row.level,
        remainingSeconds = math.max(0, math.ceil((row.expires_at - now) / 1000)),
        closeRefund = math.floor(math.max(0, row.expires_at - now) / period * Config.Locations[row.location].rentalPrice * 0.5),
        expires = os.date('!%Y-%m-%d %H:%M UTC', math.floor(row.expires_at / 1000)) }
end
lib.callback.register('tg_lockersystem:status', function(source, location)
    local ctx, err = context(source, location)
    if not ctx then return { error = err } end
    return status(rentals[key(ctx.owner, location)])
end)

lib.callback.register('tg_lockersystem:action', function(source, location, action)
    local ctx, err = context(source, location)
    if not ctx then return { error = err } end
    local rentalKey = key(ctx.owner, location)
    if busy[rentalKey] or (lastRequest[source] or 0) > GetGameTimer() then
        return { error = 'Please wait before trying again.' }
    end
    lastRequest[source] = GetGameTimer() + 750
    busy[rentalKey] = true
    local paid, committed = 0, false
    local ok, result = xpcall(function()
        local row = rentals[rentalKey]
        if action == 'open' then
            if not allowed(source, row) then return { error = 'Rent or renew your locker first.' } end
            register(row)
            return { stash = row.stash }
        end
        local price, level, expires
        local now = nowMillis()
        if action == 'close' then
            if not row then return { error = 'You do not have a locker here.' } end
            row.closing = true
            local inventory = exports.ox_inventory:GetInventory(row.stash)
            if not inventory or not inventory.items then
                row.closing = nil
                return { error = 'Could not check locker contents. Try again.' }
            end
            if next(inventory.items) then
                row.closing = nil
                return { error = 'Empty your locker before closing it.' }
            end
            local refund = math.floor(math.max(0, row.expires_at - now) / period * Config.Locations[location].rentalPrice * 0.5)
            local deleted = MySQL.update.await('DELETE FROM tg_lockersystem WHERE id = ?', { row.id })
            assert(deleted == 1, 'Locker closure failed')
            local refunded, accepted = true, true
            if refund > 0 then refunded, accepted = pcall(Bridge.refund, ctx.player, refund) end
            if not refunded or accepted == false then
                MySQL.insert.await('INSERT INTO tg_lockersystem (id, owner, location, level, expires_at) VALUES (?, ?, ?, ?, ?)',
                    { row.id, row.owner, row.location, row.level, row.expires_at })
                row.closing = nil
                return { error = 'Refund failed. Your rental has been restored.' }
            end
            committed = true
            rentals[rentalKey], byStash[row.stash] = nil, nil
            exports.ox_inventory:RemoveInventory(row.stash)
            return { success = true, refund = refund }
        elseif action == 'rent' then
            if row then return { error = 'You already have a locker here. Use renew.' } end
            price, level, expires = Config.Locations[location].rentalPrice, 1, now + period
        elseif action == 'renew' then
            if not row then return { error = 'Rent a locker first.' } end
            if not canRenew(row, now) then
                return { error = ('Renewal is available during the last %s days before expiry or any time after expiry.'):format(Config.RenewalWindowDays) }
            end
            price, level, expires = Config.Locations[location].rentalPrice, row.level, math.max(now, row.expires_at) + period
        elseif action == 'upgrade' then
            if not row or row.expires_at <= now then return { error = 'An active rental is required.' } end
            level = row.level + 1
            if not Config.Levels[level] then return { error = 'Your locker is already at the maximum level.' } end
            price, expires = Config.Levels[level].price, row.expires_at
        else return { error = 'Invalid action.' } end
        assert(type(price) == 'number' and price >= 0 and price % 1 == 0, 'Invalid price')
        if price > 0 then
            if not Bridge.pay(ctx.player, price) then return { error = 'Insufficient funds.' } end
            paid = price
        end
        if row then
            local changed = MySQL.update.await('UPDATE tg_lockersystem SET level = ?, expires_at = ? WHERE id = ?',
                { level, expires, row.id })
            assert(changed == 1, 'Rental update failed')
            committed = true
            row.level, row.expires_at = level, expires
        else
            local id = MySQL.insert.await('INSERT INTO tg_lockersystem (owner, location, level, expires_at) VALUES (?, ?, ?, ?)',
                { ctx.owner, location, level, expires })
            assert(id, 'Rental creation failed')
            committed = true
            row = { id = id, owner = ctx.owner, location = location, level = level, expires_at = expires }
            rentals[rentalKey] = row
        end
        register(row)
        return { success = true }
    end, debug.traceback)
    busy[rentalKey] = nil
    if rentals[rentalKey] then rentals[rentalKey].closing = nil end
    if not ok then
        if paid > 0 and not committed then Bridge.refund(ctx.player, paid) end
        print(('tg_lockersystem action failed: %s'):format(result))
        return { error = committed and 'Rental saved. Please reopen the menu.' or 'Transaction failed; payment refunded if charged.' }
    end
    return result
end)
AddEventHandler('playerDropped', function() lastRequest[source] = nil end)
