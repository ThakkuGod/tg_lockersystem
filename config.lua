Config = {}
Config.Framework = 'auto' -- auto, qbox, qb, esx
Config.PaymentAccount = 'cash' -- bank or cash
Config.RentalDays = 30
Config.RenewalWindowDays = 3 -- Show/allow renewal only within this many days before expiry.
Config.ExpiryReminders = {
    enabled = true,
    phone = 'auto', -- auto, sd_phone (sd-phone), gksphone, custom
    daysBefore = 3, -- Send when fewer than this many days remain, before expiry.
    checkInterval = 60000, -- Milliseconds; failed/unavailable deliveries retry next check.
    sender = 'Locker Clerk',
    senderEmail = 'lockers@city.local',
    subject = 'Your locker rental expires soon',
    -- For custom phones, edit LockerMail.customSend in server/mail.lua.
}
Config.AccessDistance = 3.0
Config.TargetDistance = 2.0
-- Exact ox_inventory item names. Uncomment/add entries to block locker deposits.
Config.RestrictedItems = {
    -- ['WEAPON_PISTOL'] = true,
    -- ['black_money'] = true,
}
Config.Levels = {
    { label = 'Small', slots = 25, weight = 50000, price = 0 },
    { label = 'Medium', slots = 50, weight = 100000, price = 10000 },
    { label = 'Large', slots = 100, weight = 200000, price = 25000 },
}
-- Prices are per rental period. Weight is in grams. Level prices are upgrade costs.
-- Location IDs must remain stable: changing an ID creates a different locker.
Config.Locations = {
    legion = {
        label = 'Legion Lockers',
        coords = vec4(246.1649, -801.4720, 30.2858, 72.9721),
        ped = 's_m_m_highsec_01',
        rentalPrice = 2500,
        blip = { sprite = 478, colour = 3, scale = 0.7 },
    },
    -- Add more locations with unique keys, e.g. sandy = { ... }.
}
