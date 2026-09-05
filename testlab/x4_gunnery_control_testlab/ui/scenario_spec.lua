X4GunneryTestLabScenarioSpec = {
    id      = "issue-83-b4-b1-diagnostic-r1",
    enabled = false,

    location = {
        sectorMacro = "Cluster_29_Sector001_macro",
        x = 500000,
        y = 0,
        z = 0,
    },

    setup = {
        remote          = true,
        shipMacro       = "ship_par_l_destroyer_01_a_macro",
        shipLabel       = "ISSUE83 B4 B1 SHOOTER 1",
        turretGroup     = "group_rear_down_mid",
        turretLabel     = "Rear Lower Mid Beam",
        expectedTurrets = 1,
        expectedMemberMacros = {
            "turret_par_l_beam_01_mk1_macro",
        },
        selectAll = false,
    },

    groups = {
        {
            label     = "ISSUE83 B4 B1 SHOOTER",
            macro     = "ship_par_l_destroyer_01_a_macro",
            faction   = "player",
            count     = 1,
            distance  = 1,
            x         = 0,
            y         = 0,
            spread    = 0,
            behaviour = "wait",

            role      = "shooter",
            loadout   = "x4gc_testlab_par_l_destroyer_01_beam_plasma",
            expectedWeapons        = 2,
            expectedTurrets        = 2,
            expectedMissileTurrets = 0,
        },

        {
            label     = "ISSUE83 B4 B1 CENTER",
            macro     = "ship_arg_l_destroyer_02_a_macro",
            faction   = "xenon",
            count     = 1,
            distance  = -4000,
            x         = 0,
            y         = -4000,
            spread    = 0,
            behaviour = "wait",
            hostile   = true,
            holdFire  = true,
            stripDefenceUnits = true,
            repairGuard       = true,
        },

        {
            label     = "ISSUE83 B4 B1 RIGHT",
            macro     = "ship_arg_l_destroyer_02_a_macro",
            faction   = "xenon",
            count     = 1,
            distance  = -2500,
            x         = 3000,
            y         = -5500,
            spread    = 0,
            behaviour = "wait",
            hostile   = true,
            holdFire  = true,
            stripDefenceUnits = true,
            repairGuard       = true,
        },

        {
            label     = "ISSUE83 B4 B1 LEFT",
            macro     = "ship_arg_l_destroyer_02_a_macro",
            faction   = "xenon",
            count     = 1,
            distance  = -2500,
            x         = -3000,
            y         = -5500,
            spread    = 0,
            behaviour = "wait",
            hostile   = true,
            holdFire  = true,
            stripDefenceUnits = true,
            repairGuard       = true,
        },
    },
}

return X4GunneryTestLabScenarioSpec
