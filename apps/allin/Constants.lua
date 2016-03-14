local _M = {}

-- redis channels
_M.TABLE_CHAT_CHANNEL_PREFIX            = "_TABLE_CHAT_"

_M.MESSAGE_FORMAT_JSON                  = "json"

_M.Snap = {
    SnapType = {
        SnapGameState       = 0x01,
        SnapTable           = 0x02,
        SnapCards           = 0x03,
        SnapWinAmount       = 0x06,
        SnapWinPot          = 0x07,
        SnapOddChips        = 0x08,
        SnapPlayerAction    = 0x0a,
        SnapPlayerCurrent   = 0x0b,
        SnapPlayerShow      = 0x0c
    },

    GameState = {
        SnapGameStateStart      = 0x01,
        SnapGameStateEnd        = 0x02,
        SnapGameStateSeat       = 0x03, 
        SnapGameStateNewHand    = 0x04,
        SnapGameStateBlinds     = 0x05,
        SnapGameStateWon        = 0x10,
        SnapGameStateBroke      = 0x11,
        SnapGameStateExpire     = 0x12,
        SnapGameStatePause      = 0x13,
        SnapGameStateResume     = 0x14,
    },

    TableState = {
        GameStart       = 0,
        ElectDealer     = 1,
        NewRound        = 2,
        Blinds          = 3,
        Betting         = 4,
        BettingEnd      = 5, -- pseudo-state 
        AskShow         = 6,
        AllFolded       = 7,
        Showdown        = 8,
        EndRound        = 9
    },

    CardType = {
        SnapCardsHole       = 0x1,
        SnapCardsFlop       = 0x2,
        SnapCardsTurn       = 0x3,
        SnapCardsRiver      = 0x4
    },

    PlayerAction = {
        SnapPlayerActionFolded  = 0x01,  
        SnapPlayerActionChecked = 0x02, 
        SnapPlayerActionCalled  = 0x03,
        SnapPlayerActionBet     = 0x04,
        SnapPlayerActionRaised  = 0x05,
        SnapPlayerActionAllin   = 0x06,
    }
}

_M.OK = 0
_M.Error = {
    ArgumentNotSet      = 1,
    AllinError          = 2,
    RedisError          = 3,
    MysqlError          = 4,
    DataBaseError       = 5,
    PermissionDenied    = 6,
    NotExist            = 7,
    LogicError          = 8,
    LeanCloudError      = 9,
    InternalError       = 100
}

_M.GameMode = {
    GameModeRingGame    = 0x01, -- Cash game
    GameModeFreezeOut   = 0x02, -- MTT
    GameModeSNG         = 0x03  -- SNG
}

_M.Limit = {
    ListClubLimit = 50,
    ListGameLimit = 20
}

return table.readonly(_M)
