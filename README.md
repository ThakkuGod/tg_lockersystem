# tg_lockersystem

Personal locker rentals for ESX, Qbox, and QBCore using ox_inventory.

## Features

- Multiple ped locations with ox_target and ox_lib menus.
- 30-day rentals with remaining days, renewals, and capacity upgrades.
- Restricted items and empty-locker closure with a partial refund.
- Phone expiry reminders through sd-phone, GKSPhone, or a custom adapter.

## Installation

Requires OneSync, a supported framework, oxmysql, ox_lib, ox_target, and ox_inventory configured for that framework. QBCore requires a compatible ox_inventory bridge.

Start dependencies first, then add to server.cfg:

```cfg
ensure tg_lockersystem
```

Database tables are created automatically. After configuration changes, run `restart tg_lockersystem`.

## Configuration

Edit `config.lua` to set locations, ped models, rental prices, levels, payment account, and restricted items. Weights are in grams. Keep existing location keys and level indices unchanged.

For phone reminders, set `Config.ExpiryReminders.phone` to `auto`, `sd_phone`, `gksphone`, or `custom`. Custom mail integration is in `server/mail.lua`. Players need a valid phone mailbox.

## Rental Rules

- Renew during the last 3 days before expiry or any time after expiry.
- Expired lockers remain saved but cannot be opened until renewed.
- Renewing after expiry starts a fresh 30-day rental; items and upgrades remain.
- Upgrades increase capacity without changing expiry.
- Closing requires an empty locker and refunds 50% of unused rental value, excluding upgrades. Example: $2,500 rent with 15 of 30 days left refunds $625.
- Reminders send once per expiry when fewer than 3 days remain.

Back up rental tables and ox_inventory data together. Test payments, storage, and phone delivery before going live.

## Report Issues

Report bugs and issues on [GitHub Issues](https://github.com/ThakkuGod/tg_lockersystem/issues).
