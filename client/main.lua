local peds, blips, pending = {}, {}, false
local showMenu
local function notify(message, kind)
    lib.notify({ title = 'Locker Clerk', description = message, type = kind or 'error' })
end
local function perform(location, action, price)
    if pending then return end
    if action ~= 'open' then
        local content = action == 'close'
            and ('Close your empty locker? Estimated refund: $%s to your %s (50%% of unused rental time). Upgrades are lost without refund.'):format(price, Config.PaymentAccount)
            or ('Confirm %s for $%s from your %s?'):format(action, price, Config.PaymentAccount)
        local answer = lib.alertDialog({ header = 'Locker Clerk',
            content = content,
            centered = true, cancel = true })
        if answer ~= 'confirm' then showMenu(location) return end
    end
    pending = true
    local ok, result = pcall(lib.callback.await, 'tg_lockersystem:action', false, location, action)
    pending = false
    if not ok or not result then notify('Could not contact the locker service.') return end
    if result.error then notify(result.error) showMenu(location) return end
    if result.stash then
        exports.ox_inventory:openInventory('stash', result.stash)
    else
        notify(result.refund ~= nil and ('Locker closed. Refunded $%s.'):format(result.refund)
            or 'Locker updated successfully.', 'success')
        showMenu(location)
    end
end
showMenu = function(location)
    if pending then return end
    pending = true
    local ok, data = pcall(lib.callback.await, 'tg_lockersystem:status', false, location)
    pending = false
    if not ok or not data then notify('Could not contact the locker service.') return end
    if data.error then notify(data.error) return end
    local loc, options = Config.Locations[location], {}
    local rentalTitle = ('Rental: %s days'):format(Config.RentalDays)
    if data.rented then
        local remaining = data.remainingSeconds
        if remaining <= 0 then
            rentalTitle = 'Rental: Expired'
        else
            local days = math.floor(remaining / 86400)
            rentalTitle = ('Rental: %s Days'):format(days)
        end
    end
    options[#options+1] = { title = rentalTitle,
        description = ('$%s per period • Payment: %s'):format(loc.rentalPrice, Config.PaymentAccount),
        icon = 'calendar', readOnly = true }
    if not data.rented then
        local base = Config.Levels[1]
        options[#options+1] = { title = 'Rent Locker', icon = 'key',
            description = ('%s • %s slots • %s kg'):format(base.label, base.slots, base.weight / 1000),
            onSelect = function() perform(location, 'rent', loc.rentalPrice) end }
    else
        local level = Config.Levels[data.level]
        options[#options+1] = { title = ('Level %s — %s'):format(data.level, level and level.label or 'Unavailable'),
            description = ('%s • Expires: %s'):format(data.active and 'Active' or 'Expired', data.expires),
            icon = 'circle-info', readOnly = true }
        options[#options+1] = { title = 'Open Locker', icon = 'box-open', disabled = not data.active,
            onSelect = function() perform(location, 'open') end }
        if data.canRenew then
            options[#options+1] = { title = ('Renew — $%s'):format(loc.rentalPrice), icon = 'calendar-plus',
                description = data.active
                    and ('Add %s days; stored items and level are preserved.'):format(Config.RentalDays)
                    or ('Restore access for %s days from payment. Stored items and level are preserved.'):format(Config.RentalDays),
                onSelect = function() perform(location, 'renew', loc.rentalPrice) end }
        end
        local nextLevel = Config.Levels[data.level + 1]
        options[#options+1] = { title = nextLevel and ('Upgrade to Level %s — $%s'):format(data.level + 1, nextLevel.price)
                or 'Maximum Level Reached', icon = 'arrow-up', disabled = not data.active or not nextLevel,
            description = level and (nextLevel
                and ('Slots: %s → %s | Weight: %s → %s kg'):format(
                    level.slots, nextLevel.slots, level.weight / 1000, nextLevel.weight / 1000)
                or ('Current capacity: %s slots | %s kg'):format(level.slots, level.weight / 1000)),
            onSelect = function() perform(location, 'upgrade', nextLevel.price) end }
        options[#options+1] = { title = 'Close Locker', icon = 'trash',
            description = ('Estimated refund: $%s — empty locker required.'):format(data.closeRefund),
            onSelect = function() perform(location, 'close', data.closeRefund) end }
    end
    lib.registerContext({ id = 'tg_lockersystem_menu', title = loc.label, options = options })
    lib.showContext('tg_lockersystem_menu')
end

CreateThread(function()
    for id, location in pairs(Config.Locations) do
        local model = joaat(location.ped)
        if not IsModelInCdimage(model) or not IsModelAPed(model) then
            print(('tg_lockersystem: invalid ped for %s'):format(id))
        else
            lib.requestModel(model)
            local c = location.coords
            local ped = CreatePed(4, model, c.x, c.y, c.z - 1.0, c.w, false, true)
            SetEntityInvincible(ped, true)
            SetBlockingOfNonTemporaryEvents(ped, true)
            FreezeEntityPosition(ped, true)
            SetPedCanRagdoll(ped, false)
            SetModelAsNoLongerNeeded(model)
            peds[#peds+1] = ped
            exports.ox_target:addLocalEntity(ped, { { name = 'tg_locker_' .. id,
                label = 'Locker Clerk', icon = 'fa-solid fa-box-archive', distance = Config.TargetDistance,
                onSelect = function() showMenu(id) end } })
        end
        if location.blip then
            local c, settings = location.coords, location.blip
            local blip = AddBlipForCoord(c.x, c.y, c.z)
            SetBlipSprite(blip, settings.sprite)
            SetBlipColour(blip, settings.colour)
            SetBlipScale(blip, settings.scale)
            SetBlipAsShortRange(blip, true)
            BeginTextCommandSetBlipName('STRING')
            AddTextComponentString(location.label)
            EndTextCommandSetBlipName(blip)
            blips[#blips+1] = blip
        end
    end
end)
AddEventHandler('onResourceStop', function(resource)
    if resource ~= GetCurrentResourceName() then return end
    lib.hideContext(false)
    for _, ped in ipairs(peds) do
        if GetResourceState('ox_target') == 'started' then exports.ox_target:removeLocalEntity(ped) end
        DeleteEntity(ped)
    end
    for _, blip in ipairs(blips) do RemoveBlip(blip) end
end)
