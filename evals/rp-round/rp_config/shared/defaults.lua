-- rp_config: the central catalogue of tunables, one section per rp_* resource.
--
-- Every leaf below is a scalar (number, boolean or string) and becomes one dotted key:
--   RpConfigDefaults.rp_bank.transferFeePercent          -> "rp_bank.transferFeePercent"
--   RpConfigDefaults.rp_jobs.salary.ncpd[3]              -> "rp_jobs.salary.ncpd.3"
--   RpConfigDefaults.rp_zones.spawn_plaza.centre.x       -> "rp_zones.spawn_plaza.centre.x"
-- A branch (a table) is also addressable: get("rp_bank.atms.atm_spawn.position") answers
-- { x, y, z } assembled from its leaves, and set() with a table writes every leaf.
--
-- The values are the CURRENT values of each resource's own shared/config.lua (or README when
-- the resource has no config file), copied on 2026-09-18. They are documentation as much as
-- defaults: an override only exists in SQL, this file is never rewritten by the resource.
-- tools/migrate-configs.md maps every key back to the field it mirrors.
--
-- Type rules enforced by set(): an integer default only accepts integral numbers, a float
-- default accepts any number, a boolean only a boolean, a string only a string (<= 1024 bytes).
-- Write floats with a decimal point (3.0) when the consuming resource expects a float.
--
-- Loaded on the server only (see open77.lua). Nothing here is secret.

RpConfigDefaults = {

    -- rp_config itself.
    rp_config = {
        chatListMax = 30,          -- /config list from chat prints at most this many lines
    },

    -- rp_economy (README: no config file). Cash wallet.
    rp_economy = {
        startingBalance = 500,             -- a new wallet
        payday = { amount = 200, intervalMinutes = 10 },
    },

    -- rp_bank/config.lua (Config.*)
    rp_bank = {
        transferFeePercent = 1,            -- Config.TransferFeePercent (/virement fee, %)
        transferFeeMin = 1,                -- Config.TransferFeeMin
        historyLimit = 10,                 -- Config.HistoryLimit
        atmRange = 3.0,                    -- Config.AtmRange
        atmPromptRange = 5.0,              -- Config.AtmPromptRange
        atmHeightTolerance = 4.0,          -- Config.AtmHeightTolerance
        maxAmount = 1000000000,            -- Config.MaxAmount
        atms = {                           -- Config.Atms[i].position, by id
            atm_spawn = { position = { x = 381.0, y = -2401.0, z = 182.0 } },
            atm_north = { position = { x = 381.0, y = -2376.0, z = 182.0 } },
            atm_east  = { position = { x = 416.0, y = -2401.0, z = 182.0 } },
            atm_south = { position = { x = 381.0, y = -2446.0, z = 182.0 } },
            atm_west  = { position = { x = 326.0, y = -2416.0, z = 182.0 } },
        },
    },

    -- rp_needs (README: no config file). Per-minute decay and the clock.
    rp_needs = {
        decayPerMinute = { hunger = 0.8, thirst = 1.2, fatigue = 0.4 },
        fatigueRecoveryPerMinute = 2.0,    -- seated in a vehicle, still
        tickSeconds = 10,
        saveSeconds = 60,
    },

    -- rp_inventory/shared/items.lua (RpInventoryConfig.*)
    rp_inventory = {
        maxCarryWeight = 40.0,
        defaultStashCapacity = 100.0,
        interactDistance = 3.0,
        dropTtlMs = 1800000,
        useDurationMs = 3000,
    },

    -- rp_jobs/shared/config.lua (RpJobsConfig.*)
    rp_jobs = {
        salary = {                         -- RpJobsConfig.Jobs[i].salary[grade], by job name
            ncpd        = { [0] = 300, [1] = 450, [2] = 600, [3] = 800 },
            trauma      = { [0] = 300, [1] = 450, [2] = 600, [3] = 800 },
            delamain    = { [0] = 200, [1] = 300, [2] = 400, [3] = 550 },
            mecano      = { [0] = 200, [1] = 300, [2] = 400, [3] = 550 },
            ripper      = { [0] = 250, [1] = 400, [2] = 550, [3] = 750 },
            nomade      = { [0] = 180, [1] = 260, [2] = 360, [3] = 500 },
            ferrailleur = { [0] = 150, [1] = 220, [2] = 300, [3] = 420 },
            barman      = { [0] = 150, [1] = 220, [2] = 300, [3] = 420 },
            fixer       = { [0] = 250, [1] = 400, [2] = 550, [3] = 750 },
            netrunner   = { [0] = 250, [1] = 400, [2] = 550, [3] = 750 },
            vigile      = { [0] = 180, [1] = 260, [2] = 360, [3] = 500 },
        },
        payrollIntervalMs = 600000,        -- RpJobsConfig.PayrollIntervalMs
        societyStartingFund = 50000,       -- RpJobsConfig.SocietyStartingFund
        hireDistance = 5.0,                -- RpJobsConfig.HireDistance
        nameplateMaxDistance = 40,         -- RpJobsConfig.NameplateMaxDistance
        agency = {                         -- RpJobsConfig.Agency
            position = { x = 396.0, y = -2388.0, z = 181.99 },
            radius = 1.5,
            promptDistance = 3.0,
            reach = 12.0,
        },
    },

    -- rp_zones/shared/config.lua (Config.zones[i] by name, Config.tickMs, Config.hysteresis)
    rp_zones = {
        tickMs = 500,
        hysteresis = 1.0,
        spawn_plaza = { centre = { x = 381.36, y = -2401.79, z = 181.99 }, radius = 45.0 },
        ncpd_hq     = { centre = { x = 440.0,  y = -2366.0,  z = 181.0 },  radius = 12.0 },
        hospital    = { centre = { x = 400.0,  y = -2366.0,  z = 182.0 },  radius = 12.0 },
        afterlife   = { centre = { x = 360.0,  y = -2390.0,  z = 182.0 },  radius = 10.0 },
        mecano_shop = { centre = { x = 341.0,  y = -2401.0,  z = 180.3 },  radius = 10.0 },
        scrapyard   = { centre = { x = 462.0,  y = -2352.0,  z = 178.0 },  radius = 12.0 },
        blackmarket = { centre = { x = 400.0,  y = -2390.0,  z = 182.0 },  radius = 10.0 },
        nomad_camp  = { centre = { x = 420.0,  y = -2378.0,  z = 182.0 },  radius = 9.0 },
        badlands    = { centre = { x = 381.36, y = -2401.79, z = 181.99 }, radius = 900.0 },
    },

    -- rp_ncpd/shared/config.lua (Config.*)
    rp_ncpd = {
        cell = { x = 436.0, y = -2362.0, z = 181.5, heading = 180.0, radius = 6.0 },
        entrance = { x = 430.0, y = -2369.0, z = 182.0, heading = 90.0 },
        actionDistance = 3.0,
        menuDistance = 3.5,
        vehicle = { range = 5.0, lockExit = true, preferRear = true },
        prison = { minMinutes = 1, maxMinutes = 120, notifyEverySeconds = 60, leashCheckMs = 5000, persistEverySeconds = 60 },
        fine = { min = 1, max = 100000, inviteTimeoutMs = 30000, autoWarrantLevel = 1 },
        warrant = { nativeHeat = false },
        alert = { blipMs = 60000 },
        grantKitRights = false,
    },

    -- rp_trauma/shared/config.lua (Config.*)
    rp_trauma = {
        downSeconds = 60,                  -- production: 600
        countdownWithoutMedics = true,     -- production: false
        hospitalBill = 500,
        healFee = 100,
        reviveFee = 300,
        stabiliseMs = 5000,
        reviveMs = 8000,
        actionRange = 3.0,
        commandRange = 5.0,
        downHealthFraction = 0.05,
        reviveHealthFraction = 0.5,
        reviveGraceMs = 5000,
        medicCooldownSeconds = 10,
        downReminderSeconds = 30,
        contractPrice = 1000,
        contractMinutes = 30,
        contractMaxFailures = 2,
        hospital = {
            respawn = { x = 400.0, y = -2366.0, z = 182.0 },
            heading = 180.0,
        },
        av = { spawnDistance = 8.0, spawnUp = 1.0, ttlMs = 1800000 },
    },

    -- rp_delamain/shared/config.lua (RpDelamainConfig.*)
    rp_delamain = {
        baseFare = 50,
        perHundredMetres = 15,
        driverShare = 0.80,
        autoEndMetres = 100,
        sampleMs = 2000,
        waitTimeoutSec = 180,
        pickupTimeoutSec = 900,
        ratingWindowSec = 900,
        blipTtlSec = 180,
        waypointRefreshM = 8,
    },

    -- rp_mecano/shared/config.lua (Config.*)
    rp_mecano = {
        repair = { reach = 4.0, durationMs = 15000, components = 2, requireToolkit = true },
        tow = { reach = 8.0, tickMs = 2000, distance = 6.0, minMove = 0.3 },
        paint = { reach = 6.0, price = 250 },
        bill = { reach = 10.0, timeoutMs = 60000, max = 50000, mechanicShare = 0.7 },
        impound = { reach = 8.0, fee = 100, testingReach = 6.0 },
        impoundAnywhereForTesting = false,
        fuel = { reach = 4.0 },
    },

    -- rp_ferrailleur/shared/config.lua (RpFerrailleurConfig.*)
    rp_ferrailleur = {
        searchReach = 3.5,
        heightTolerance = 4.0,
        searchMs = 8000,
        regenMs = 300000,
        crowbar = { durability = 20, price = 250 },
        basePrices = { scrap = 15, component = 60, chip = 200 },
        priceVariation = 0.20,
        priceIntervalMs = 600000,
        societyShare = 0.10,
        dealer = { position = { x = 462.0, y = -2352.0, z = 178.0 }, yaw = 200.0, reach = 5.0 },
        points = {                         -- Config.points[i] (wreck collection points)
            [1] = { x = 456.0, y = -2356.0, z = 178.0 },
            [2] = { x = 461.0, y = -2359.0, z = 178.0 },
            [3] = { x = 467.0, y = -2357.0, z = 178.0 },
            [4] = { x = 469.0, y = -2351.0, z = 178.0 },
            [5] = { x = 465.0, y = -2346.0, z = 178.0 },
            [6] = { x = 459.0, y = -2346.0, z = 178.0 },
            [7] = { x = 455.0, y = -2350.0, z = 178.0 },
        },
        ringRadius = 1.2,
        promptDistance = 3.0,
    },

    -- rp_nomade/shared/config.lua (RpNomadeConfig.*)
    rp_nomade = {
        camp = {
            position = { x = 420.0, y = -2378.0, z = 182.0 },
            board = { position = { x = 420.0, y = -2381.5, z = 182.0 }, radius = 1.0, promptDistance = 3.0, reach = 5.0 },
            truckSpawn = { x = 427.0, y = -2381.0, z = 182.3, yaw = 180.0 },
        },
        contract = {
            payPerCrate = 150,
            convoyBonus = 0.25,
            convoyRadius = 30.0,
            convoyMinimum = 2,
            societyShare = 0.15,
            timeLimitMs = 1200000,
            unloadMs = 6000,
            historyRows = 10,
        },
        truck = { rental = 100, reach = 4.0, ttlMs = 2400000 },
        crate = { pickupDistance = 3.5, promptDistance = 3.0 },
        ambush = {
            enabled = true,
            center = { x = 410.0, y = -2384.0, z = 182.0 },
            radius = 20.0,
            minTravel = 10.0,
            count = 3,
            spawnDistance = 15.0,
            lifetimeMs = 180000,
        },
    },

    -- rp_bar/shared/config.lua (RpBarConfig.*)
    rp_bar = {
        counter = { position = { x = 360.0, y = -2390.0, z = 181.99 }, promptDistance = 3.0, radius = 1.5, reach = 8.0 },
        drinks = {                         -- RpBarConfig.drinks[id].price / .alcohol
            beer              = { price = 30,  alcohol = 1 },
            whisky            = { price = 60,  alcohol = 2 },
            johnny_silverhand = { price = 120, alcohol = 3 },
            synth_soda        = { price = 20,  alcohol = 0 },
        },
        ingredients = {                    -- RpBarConfig.ingredients[id].cost
            ingredient_spirits = { cost = 40 },
            ingredient_mixer   = { cost = 15 },
            ingredient_ice     = { cost = 10 },
        },
        craft = { durationMs = 4000 },
        sale = { tillShare = 0.70, distance = 3.0, inviteTimeoutMs = 20000, durationMs = 4000, breakDistance = 5.0 },
        drunk = { max = 10, tickMs = 60000, screenAbove = 3, stumbleAbove = 7, stumbleDurationMs = 2000 },
        ambience = { radius = 30.0, stopRadius = 34.0, volume = 0.5, sweepMs = 5000 },
    },

    -- rp_ripperdoc/shared/config.lua (RpRipperConfig.*)
    rp_ripperdoc = {
        chair = { position = { x = 400.0, y = -2386.0, z = 182.0 }, yaw = 90.0, promptDistance = 3.0, reach = 3.5, radius = 1.2 },
        operateDistance = 4.0,
        quoteTimeoutMs = 30000,
        removalPriceFactor = 0.5,
        restockPriceFactor = 0.6,
        restockMaxCount = 5,
        cyberpsychosisThreshold = 4,
        cyberpsychosisDurationSeconds = 60,
        grades = {                         -- RpRipperConfig.catalogue[key].grades[id].price / .durationMs
            arms  = { street = { price = 1500, durationMs = 15000 }, industrial = { price = 3200, durationMs = 22000 } },
            legs  = { training = { price = 1200, durationMs = 12000 }, athlete = { price = 2500, durationMs = 18000 } },
            deck  = { street = { price = 2000, durationMs = 20000 } },
            ice   = { street = { price = 1800, durationMs = 14000 } },
            purge = { street = { price = 1600, durationMs = 14000 } },
        },
    },

    -- rp_fixer/shared/config.lua (Config.*)
    rp_fixer = {
        openBoardWithoutFixer = true,
        office = { x = 400.0, y = -2390.0, z = 182.0 },
        boardReach = 15.0,
        promptDistance = 3.0,
        interactReach = 4.5,
        arrivalDistance = 5.0,
        commissionRate = 0.15,
        reputation = { success = 1, abandoned = -1, timeout = -1, floor = 0 },
        maxOpenGigs = 20,
        autoPublish = true,
        republishDelaySec = 60,
        warnBeforeDeadlineSec = 60,
        guards = { count = 2, health = 150, postRadius = 3.0, guardRadius = 8, engageDistance = 25.0 },
        templates = {                      -- Config.templates[id].pay / .timeLimitSec
            delivery_meds     = { pay = 600,  timeLimitSec = 600 },
            escort_witness    = { pay = 800,  timeLimitSec = 720 },
            retrieval_shard   = { pay = 1000, timeLimitSec = 720 },
            extraction_techie = { pay = 1500, timeLimitSec = 900 },
            delivery_hot      = { pay = 1200, timeLimitSec = 360 },
            extraction_vip    = { pay = 3000, timeLimitSec = 900 },
        },
    },

    -- rp_netrunner/shared/config.lua (Config.*)
    rp_netrunner = {
        cooldownMs = 30000,
        traceChance = 0.5,
        deck = { price = 0 },
        hacks = {
            short_circuit = { range = 25, uploadMs = 2000, staminaCost = 20, damage = 25, statusMs = 750, recoveryMs = 4000 },
            overheat      = { range = 25, uploadMs = 2500, staminaCost = 20, damage = 10, statusMs = 750, recoveryMs = 4000 },
        },
        ping = { range = 50, durationMs = 60000, refreshMs = 2000, warnTarget = false },
        jam = { durationMs = 60000, noiseEveryMs = 15000 },
        accessPoint = { position = { x = 400.0, y = -2390.0, z = 182.0 }, radius = 1.2, promptDistance = 3.0, reach = 4.0 },
        breach = { durationMs = 10000, doorRadius = 15.0, doorHoldMs = 30000, bounty = 200, societyBounty = 100 },
    },

    -- rp_vigile/shared/config.lua (VigileConfig.*)
    rp_vigile = {
        ratePerMinute = 20,
        societyShare = 0.20,
        minMinutes = 1,
        maxMinutes = 240,
        bodyguardRange = 15.0,
        minuteCoverage = 0.75,
        tickMs = 5000,
        unpaidWarnAfter = 2,
        offerTimeoutSec = 180,
        zoneOfferTimeoutSec = 1800,
        escortRange = 3.0,
        escortHoldMs = 120000,
        expelDistance = 20.0,
        journalSize = 50,
        templates = {                      -- VigileConfig.templates[i].minutes, by zone
            afterlife   = { minutes = 30 },
            blackmarket = { minutes = 30 },
            mecano_shop = { minutes = 20 },
            nomad_camp  = { minutes = 20 },
            scrapyard   = { minutes = 20 },
            hospital    = { minutes = 20 },
        },
    },

    -- rp_garage/shared/config.lua (Config.*)
    rp_garage = {
        garages = {                        -- Config.garages[i], by id
            public = {
                position = { x = 370.0, y = -2405.0, z = 182.0 },
                spawnPoint = { x = 364.0, y = -2406.0, z = 182.0, yaw = 90.0 },
            },
            mecano = {
                position = { x = 341.0, y = -2401.0, z = 180.3 },
                spawnPoint = { x = 347.0, y = -2405.0, z = 180.5, yaw = 90.0 },
            },
        },
        dealership = {
            position = { x = 392.0, y = -2410.0, z = 182.0 },
            spawnPoint = { x = 392.0, y = -2404.0, z = 182.0, yaw = 0.0 },
        },
        vehicles = {                       -- Config.vehicles[i].price, keyed by a slug of the label
            archer_hella              = { price = 15000 },  -- Vehicle.v_standard2_archer_hella_player
            arch_nazare               = { price = 12000 },  -- Vehicle.v_sportbike2_arch_player
            thorton_mackinaw          = { price = 28000 },  -- Vehicle.v_standard3_thorton_mackinaw_player
            villefort_cortes_delamain = { price = 45000 },  -- Vehicle.v_standard2_villefort_cortes_delamain_player
            quadra_turbo_r            = { price = 60000 },  -- Vehicle.v_sport1_quadra_turbo_player
        },
        impound = { fee = 500, lotPosition = { x = 440.0, y = -2366.0, z = 181.0 } },
        reach = { prompt = 3.0, garage = 6.0, store = 8.0, lock = 6.0, plate = 8.0, key = 5.0, keyVehicle = 8.0, height = 4.0 },
        spawnTries = 3,
        spawnStep = 4.5,
        spawnClearance = 3.0,
        minHealthOnTakeOut = 0.2,
        snapshotIntervalMs = 30000,
        stolenCooldownS = 300,
        menuTimeoutMs = 60000,
        confirmTimeoutMs = 30000,
    },

    -- rp_shops/shared/config.lua (RpShopsConfig.*)
    rp_shops = {
        reach = 3.5,
        promptDistance = 3.0,
        societyShare = 0.70,
        restockCostRatio = 0.5,
        gunLicenceFee = 500,
        stylingFee = 200,
        blackmarket = { openHour = 22, closeHour = 6 },
        robLoot = { min = 200, max = 600 },
        robCooldownSeconds = 1200,
        robDistance = 5.0,
        robHandsUpMs = 20000,
        robTakesFromSociety = true,
        maxCountPerPurchase = 20,
        weaponFallbackMs = 15000,
        shops = {                          -- RpShopsConfig.shops[i], by id; prices by catalogue id
            supermarket = {
                position = { x = 370.0, y = -2385.0, z = 181.99 }, yaw = 214.0,
                prices = { water = 10, burrito = 25, nicola = 15, chooh2 = 60, cigarettes = 20 },
            },
            pharmacy = {
                position = { x = 396.0, y = -2372.0, z = 181.99 }, yaw = 154.0,
                restockTo = 10,
                prices = { bandage = 40, maxdoc = 120, bounceback = 90 },
            },
            gunshop = {
                position = { x = 410.0, y = -2386.0, z = 181.99 }, yaw = 119.0,
                prices = { pistol = 400, rifle = 1200, katana = 900 },
            },
            clothes = {
                position = { x = 352.0, y = -2398.0, z = 181.99 }, yaw = 263.0,
                prices = { styling = 200 },
            },
            blackmarket = {
                position = { x = 402.0, y = -2393.0, z = 181.99 }, yaw = 113.0,
                prices = { synthcoke = 150, lockpick = 80, qh_ping = 120 },
            },
        },
    },

    -- rp_housing/shared/config.lua (Config.*)
    rp_housing = {
        rent = 500,
        rentIntervalSec = 600,
        rentTickSec = 60,
        evictAfter = 2,
        sellBackRatio = 0.70,
        promptDistance = 3.0,
        serverTolerance = 2.5,
        agencyRadius = 4.0,
        keyDistance = 3.0,
        interiorRadius = 8.0,
        enterFade = 400,
        spawnWaitSec = 30,
        stashCapacity = 200,
        agency = { position = { x = 365.0, y = -2408.0, z = 182.0 }, radius = 1.5 },
        homes = {                          -- Config.homes[i], by id
            northside_container = { price = 9000,
                entrance = { x = 348.0, y = -2386.0, z = 182.0 }, interior = { x = 342.0, y = -2386.0, z = 182.0 } },
            badlands_hideout = { price = 15000,
                entrance = { x = 352.0, y = -2404.0, z = 182.0 }, interior = { x = 352.0, y = -2410.0, z = 182.0 } },
            h10_studio = { price = 25000,
                entrance = { x = 376.0, y = -2380.0, z = 182.0 }, interior = { x = 376.0, y = -2374.0, z = 182.0 } },
            kabuki_flat = { price = 40000,
                entrance = { x = 388.0, y = -2388.0, z = 182.0 }, interior = { x = 388.0, y = -2382.0, z = 182.0 } },
            japantown_loft = { price = 65000,
                entrance = { x = 390.0, y = -2399.0, z = 182.0 }, interior = { x = 390.0, y = -2405.0, z = 182.0 } },
        },
    },

    -- rp_hud/shared/config.lua (RpHudConfig.*)
    rp_hud = {
        minPushIntervalMs = 250,
        refreshMs = 30000,
        joinRepushMs = 6000,
        dependencyRepushMs = 4000,
        needsWarnAt = 25,
        panelWidthPx = 300,
    },

    -- rp_phone/shared/config.lua (RpPhoneConfig.*)
    rp_phone = {
        requireItem = true,
        call = { ringSeconds = 30 },
        sms = { maxLength = 200, keepPerPlayer = 300 },
        contacts = { max = 60, nearbyRadius = 8.0 },
        location = { blipSeconds = 120 },
        ads = { price = 50, minutes = 60, maxLength = 140, maxListed = 30, maxPerPlayer = 3 },
        pushThrottleMs = 250,
        intentsPerSecond = 12,
    },

    -- rp_radio/shared/config.lua (Config.*). requireItem, badlandsCut and rememberFrequency are
    -- the three keys rp_radio ALREADY reads through rp_config (its README, "Configuration").
    rp_radio = {
        requireItem = true,
        badlandsCut = false,
        rememberFrequency = true,
        rememberDelayMs = 4000,
        maxTextLength = 200,
        band = { min = 87.5, max = 108.0, step = 0.1 },
        jam = { localGain = 0.5, staticIntervalMs = 15000, garbleText = true, garbleRatio = 0.45 },
    },

    -- rp_gangs/shared/config.lua (RpGangsConfig.*)
    rp_gangs = {
        openFounding = true,
        dropOnJob = true,
        showTag = true,
        tagMaxDistance = 40.0,
        recruitReach = 5.0,
        dealInfluence = 1,
        gigInfluence = 2,
        arrestInfluence = -5,
        tributePerZone = 50,
        tributeIntervalMs = 600000,
        buyer = { reach = 4.0, promptDistance = 2.5 },
        dealPrice = 80,
        dealCooldownMs = 60000,
        robShare = 0.30,
        robReach = 3.0,
        robCooldownMs = 120000,
        warMinutes = 5,                    -- production: 20
        warTickMs = 30000,
        warInfluence = 10,
        warCooldownMs = 600000,
        racketAmount = 100,
        racketReach = 5.0,
        racketCooldownMs = 60000,
        territories = {                    -- Config.territories[i].buyer, by zone name
            blackmarket = { buyer = { x = 397.0, y = -2393.0, z = 182.0, yaw = 45.0 } },
            afterlife   = { buyer = { x = 358.0, y = -2392.0, z = 182.0, yaw = 45.0 } },
            nomad_camp  = { buyer = { x = 418.0, y = -2380.0, z = 182.0, yaw = 45.0 } },
            scrapyard   = { buyer = { x = 460.0, y = -2355.0, z = 178.0, yaw = 45.0 } },
        },
    },

    -- rp_ambiance/shared/config.lua. The first eight keys are the ones rp_ambiance ALREADY
    -- reads through rp_config (Config.overrides); keep their names exactly.
    rp_ambiance = {
        realHoursPerDay = 3,               -- Config.cycle.realHoursPerDay
        weatherMinMinutes = 12,            -- Config.cycle.weatherMinMinutes
        weatherMaxMinutes = 25,            -- Config.cycle.weatherMaxMinutes
        badlands = true,                   -- Config.cycle.badlands
        noticeIntervalMinutes = 15,        -- Config.notices.intervalMinutes
        figurantsEnabled = true,           -- Config.figurants.enabled
        musicVolume = 0.35,                -- Config.music.volume
        alertsEnabled = true,              -- Config.alerts.enabled
        -- Not read by rp_ambiance yet (candidates for its Config.overrides list).
        weatherTransitionSeconds = 45,     -- Config.cycle.weatherTransitionSeconds
        announceWeather = true,            -- Config.cycle.announceWeather
        figurants = { sweepSeconds = 300, wanderRadius = 6.0, speakRadius = 8.0, speakMinSeconds = 60, speakMaxSeconds = 120 },
        notices = { enabled = true, durationMs = 10000 },
        alerts = { range = 60.0, flashes = 3, flashIntervalMs = 1200, cooldownSeconds = 8 },
    },

    -- rp_admin/shared/config.lua (RpAdminConfig.*)
    rp_admin = {
        godModeInAdminMode = true,
        maxGrade = 3,
        maxMoney = 1000000000,
        warnMaxBytes = 200,
        reportMaxBytes = 300,
        answerMaxBytes = 300,
        ticketListLimit = 20,
        recordLines = 10,
        panelTimeoutMs = 60000,
        teleportOffset = 1.5,
        spectate = { distance = 5.0, height = 2.0, blendMs = 400 },
    },

    -- rp_logs/shared/config.lua (RpLogsConfig.*). Never the webhook URL: that is a secret and
    -- stays in the server convars / the resource's own tunable.
    rp_logs = {
        flushIntervalMs = 2000,
        flushBatchSize = 50,
        pendingMax = 2000,
        cacheSize = 500,
        webhookMinIntervalMs = 1000,
        webhookQueueMax = 100,
        webhookBackoffSeconds = 5,
        defaultListCount = 10,
        maxListCount = 50,
    },

    -- rp_whitelist/shared/config.lua (Config.*). `enabled` is also persisted by rp_whitelist in
    -- its own KVP store (/wl activer), which wins over the file: see tools/migrate-configs.md.
    rp_whitelist = {
        enabled = false,
        mode = "allowlist",
        maxPlayers = 0,
        discordLink = "https://discord.open2077.net",
        queue = { holdSeconds = 6.5, pollMs = 500, ttlSeconds = 120, reserveSeconds = 10 },
        failClosed = true,
        loadWaitSeconds = 5,
        bansWhenDisabled = true,
        recentRefusals = 10,
    },
}
