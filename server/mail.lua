local LockerMail = {}

-- Server-only custom adapter. owner is the ESX character identifier or QB/Qbox
-- citizenid. Resolve this identity to your phone's recipient as needed.
-- Return true ONLY when mail is accepted; false retries on the next scan.
function LockerMail.customSend(owner, mail, rental)
    -- Example (replace with your phone's actual export):
    -- return exports['my-phone']:SendLockerMail(owner, {
    --     sender = mail.sender, subject = mail.subject, message = mail.message,
    -- }) == true
    return false
end

local function send(owner, mail, rental)
    local provider = Config.ExpiryReminders.phone
    if provider == 'auto' then
        if GetResourceState('sd-phone') == 'started' then provider = 'sd_phone'
        elseif GetResourceState('gksphone') == 'started' then provider = 'gksphone'
        else return false end
    end
    if provider == 'sd_phone' or provider == 'sd-phone' then
        if GetResourceState('sd-phone') ~= 'started' then return false end
        local accounts = exports['sd-phone']:getMailAddresses(owner)
        if not accounts or not accounts[1] then return false end
        local result = exports['sd-phone']:sendMail({
            to = accounts[1].email,
            from = { name = mail.sender, email = mail.senderEmail },
            subject = mail.subject, body = mail.message,
        })
        return result and result.success == true and (result.delivered or 0) > 0
    elseif provider == 'gksphone' then
        if GetResourceState('gksphone') ~= 'started' then return false end
        local result = exports.gksphone:SendNewMailOffline(owner, {
            sender = mail.sender, subject = mail.subject, message = mail.message,
            image = '/html/img/icons/mail.png',
        })
        -- Some GKSPhone versions have no return value; no thrown error indicates
        -- acceptance there. Explicit failure responses remain retryable.
        if type(result) == 'table' then return result.success == true or result.status == true end
        return result ~= false
    elseif provider == 'custom' then
        return LockerMail.customSend(owner, mail, rental) == true
    end
    error('Invalid Config.ExpiryReminders.phone')
end

local lastError = 0
local function scan()
    local settings = Config.ExpiryReminders
    local now = os.time() * 1000
    local rows = MySQL.query.await([[
        SELECT r.* FROM tg_lockersystem r
        LEFT JOIN tg_locker_reminders m ON m.rental_id = r.id AND m.expires_at = r.expires_at
        WHERE r.expires_at > ? AND r.expires_at < ? AND m.rental_id IS NULL
    ]], { now, now + settings.daysBefore * 86400000 })
    for _, row in ipairs(rows) do
        local location = Config.Locations[row.location]
        if location then
            row.expires_at = tonumber(row.expires_at)
            local remaining = row.expires_at - os.time() * 1000
            if remaining > 0 then
                local expiry = os.date('!%Y-%m-%d %H:%M UTC', math.floor(row.expires_at / 1000))
                local mail = {
                    sender = settings.sender, senderEmail = settings.senderEmail, subject = settings.subject,
                    message = ('Your locker at %s expires in less than %s day(s), on %s. '
                        .. 'Visit the Locker Clerk to renew for $%s. Access stops at expiry; '
                        .. 'your items and upgrades remain saved until you renew.'):format(
                            location.label, math.ceil(remaining / 86400000), expiry, location.rentalPrice),
                }
                local ok, delivered = pcall(send, row.owner, mail, row)
                if ok and delivered then
                    MySQL.insert.await('INSERT IGNORE INTO tg_locker_reminders (rental_id, expires_at) VALUES (?, ?)',
                        { row.id, row.expires_at })
                elseif not ok and GetGameTimer() - lastError > 60000 then
                    lastError = GetGameTimer()
                    print(('tg_lockersystem: reminder delivery failed: %s'):format(delivered))
                end
            end
        end
    end
end

function LockerMail.start()
    local settings = Config.ExpiryReminders
    if not settings or not settings.enabled then return end
    assert(settings.daysBefore > 0 and settings.checkInterval >= 1000, 'Invalid reminder timing')
    CreateThread(function()
        MySQL.query.await([[CREATE TABLE IF NOT EXISTS tg_locker_reminders (
            rental_id INT UNSIGNED NOT NULL,
            expires_at BIGINT NOT NULL,
            PRIMARY KEY (rental_id, expires_at)
        )]])
        while true do
            local ok, err = xpcall(scan, debug.traceback)
            if not ok then print(('tg_lockersystem: reminder scan failed: %s'):format(err)) end
            Wait(settings.checkInterval)
        end
    end)
end

return LockerMail
