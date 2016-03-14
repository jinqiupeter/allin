local Snap       = cc.class("Snap")
local Constants  = cc.import(".Constants", "..")

local string_split       = string.split
local _handleGameState, _handleTable, _handleCards, _handleWinAmount, _handleWinPot, _handleOddChips, _handlePlayerAction, _handlePlayerCurrent, _handlePlayerShow, _handleFoyer, _handleERR

_handleGameState = function (snap_value, args)
    --tcp: SNAP 1:0 1 <<1>>
    local value = {}
    local game_state = tonumber(snap_value[1])
    value.game_state = game_state

    if game_state == Constants.Snap.GameState.SnapGameStateNewHand then
        value.hand_no = snap_value[2]
    elseif game_state == Constants.Snap.GameState.SnapGameStateBroke then
        value.broken_player_id = snap_value[2]
        value.broken_player_position = snap_value[3]  -- TODO: what does this mean?
    end

    return value
end

_handleTable = function (snap_value, args)
    --tcp: SNAP 1:0 2 <<0:-1 -1 cc: s4:0:0:1500:0:0: s9:1:0:1500:0:0:   0>>
    local value = {}
    local game_id = args.game_id
    local table_id = args.table_id
    local instance = args.instance

    -- table state and bet round
    local head = table.remove(snap_value, 1)  -- same as head = array.shift()
    local tmp = string_split(head, ":")
    local table_state = tonumber(tmp[1])
    value.table_state = table_state

    -- table chat support
    if table_state == Constants.Snap.TableState.NewRound then
    -- subscribe to table channel to receive table chat
        cc.printdebug("subscribing to table channel " .. Constants.TABLE_CHAT_CHANNEL_PREFIX .. tostring(game_id) .. "_" .. tostring(table_id))
        instance:subscribe(Constants.TABLE_CHAT_CHANNEL_PREFIX .. tostring(game_id) .. "_" .. tostring(table_id))
    elseif table_state == Constants.Snap.TableState.EndRound then
    -- unsubscribe
        instance:unsubscribe(Constants.TABLE_CHAT_CHANNEL_PREFIX .. tostring(game_id) .. "_" .. tostring(table_id))
    end
        
    local bet_round    = tmp[2]
    value.bet_round = bet_round
    --[[ bet round:
    Not in bet round = -1
    Preflop     = 0,
    Flop        = 1,
    Turn        = 2,
    River       = 3
    --]]

    -- turn
    local head = table.remove(snap_value, 1)
    local turn = head
    value.turn = turn
    -- if table state is (Table::GameStart|Table::ElectDealer), then turn is -1
    -- otherwise turn is: %d:%d:%d:%d:%d, t->dealer:t->sb:t->bb:(t->cur_player == -1) ? -1 : (int)t->seats[t->cur_player].seat_no:t->last_bet_player
    if turn ~= "-1" then 
        value.turn = nil

        local tmp = string_split(turn, ":")
        value.dealer            = tmp[1]
        value.sb                = tmp[2]
        value.bb                = tmp[3]
        value.current_player    = tmp[4]
        value.last_bet_player   = tmp[5]
    end

    local head = table.remove(snap_value, 1)
    -- community cards, looks like: cc:5c:2d:Th:9c:9h or cc:
    local tmp  = string_split(head, ":")
    local community_cards = table.subrange(tmp, 2, #tmp)
    value.community_cards = community_cards


    -- occupied seats' info
    local occupied_seats = {}
    local i = 1
    local head = table.remove(snap_value, 1)
    while string.byte(head) == 115 do -- 115 = char 's'
        -- seat info looks like: s4:0:0:1500:0:0:
        local tmp = string_split(head, ":")
        local sseat_no              = tmp[1]
        local seat_no               = string.sub(sseat_no, 2)
        local player_id             = tmp[2]
        local player_state          = tmp[3]  -- PlayerInRound(0x01) | PlayerSitout(0x02) 
        local in_round = 0
        if bit.band(0x01 ,tonumber(player_state)) > 0 then 
            in_round = 0
        end
        local sit_out = 0
        if bit.band(0x02 ,tonumber(player_state)) > 0 then 
            sit_out = 0
        end
        local player_stake          = tmp[4]
        local player_stake          = tmp[4]
        local bet_amount            = tmp[5] -- bet amount
        local last_action           = tmp[6] -- 0: None, 1: ResetAction, 2: Check, 3: Fold, 4: Call, 5: Bet, 6: Raise, 7: Allin, 8: Show, 9: Muck, 10: Sitout, 11: Back
        local hole_cards            = tmp[7] or ""

        occupied_seats[i] = {seat_no = seat_no, player_id = player_id, in_round = in_round, sit_out = sit_out, player_stake = player_stake, bet_amount = bet_amount, last_action = last_action, hole_cards = hole_cards}

        head = table.remove(snap_value, 1)
        i = i + 1
    end
    value.occupied_seats = occupied_seats

    -- pots
    local pots = {}
    local i = 1
    while string.byte(head) == 112 do -- 112 = char 'p'
        -- pot info looks like: p1:30
        local tmp = string_split(head, ":")
        local spot_no              = tmp[1]
        local pot_no               = string.sub(spot_no, 2)
        local pot_amount           = tmp[2]

        pots[i] = {pot_no = pot_no, pot_amount = pot_amount}

        head = table.remove(snap_value, 1)
        i = i + 1
    end
    value.pots = pots 

    -- minimum bet amount
    value.minimus_bet = head

    return value
end

_handleCards = function (snap_value, args)
    -- tcp: SNAP 1:0 3 <1 Kc 3s>
    local value = {}
    local card_type = snap_value[1]
    value.card_type = card_type
    --[[ card_type:
    SnapCardsHole       = 0x1,
    SnapCardsFlop       = 0x2,
    SnapCardsTurn       = 0x3,
    SnapCardsRiver      = 0x4,
    --]]

    local cards = table.subrange(snap_value, 2, #snap_value)
    value.cards = cards

    return value
end

_handleWinAmount = function (snap_value, args)
    -- tcp: SNAP 1:0 6 <1 -1 60> ==><1=cid, -1=reserved, 60==>amount won>
    local value = {}
    local player_id = snap_value[1]
    value.player_id = player_id

    -- snap_value[2] is reserved
    local amount_won = snap_value[3]
    value.amount_won = amount_won

    return value
end

_handleWinPot = function (snap_value, args)
    -- tcp: SNAP 1:0 7 <1 0 120> ==><1=cid, 0=pot id, 120=amount received>
    local value = {}
    local player_id = snap_value[1]
    value.player_id = player_id

    -- snap_value[2] is reserved
    local pod_id = snap_value[2]
    value.pod_id = pod_id

    local amount_received = snap_value[3]
    value.amount_received = amount_received

    return value
end

_handleOddChips = function (snap_value, args)
    -- tcp: SNAP 1:0 8 <1 0 120> ==><1=cid, 0=>pot id, 120=amount received>
    local value = {}
    local player_id = snap_value[1]
    value.player_id = player_id

    -- snap_value[2] is reserved
    local pod_id = snap_value[2]
    value.pod_id = pod_id

    local odd_chips_received = snap_value[3]
    value.odd_chips_received = odd_chips_received

    return value
end

_handlePlayerAction = function (snap_value, args)
    -- tcp: SNAP 1:0 10 <3 1 10> ==><3=action_type, 1=cid, c=[auto_action?1:0] if action is Fold or Check, [amount] otherwise>
    local value = {}
    local action_type = tonumber(snap_value[1])
 --[[ player action type:
 SnapPlayerActionFolded  = 0x01,  // cid, auto=0|1
 SnapPlayerActionChecked = 0x02,  // cid, auto=0|1
 SnapPlayerActionCalled  = 0x03,  // cid, amount
 SnapPlayerActionBet = 0x04,      // cid, amount
 SnapPlayerActionRaised  = 0x05,  // cid, amount
 SnapPlayerActionAllin   = 0x06,  // cid, amount
 --]]
    value.action_type = action_type

    -- snap_value[2] is reserved
    local player_id = snap_value[2]
    value.player_id = player_id

    if action_type == Constants.Snap.PlayerAction.SnapPlayerActionFolded 
        or 
       action_type == Constants.Snap.PlayerAction.SnapPlayerActionChecked then
        value.auto_action = snap_value[3]
    else
        value.amount = snap_value[3]
    end

    return value
end

_handlePlayerCurrent = function (snap_value, args)
    -- tcp: SNAP 1:0 11
    local value = {msg = "not implemented"}

    return value
end

_handlePlayerShow = function (snap_value, args)
    -- tcp: SNAP 1:0 12 <0 Jh 4c 5c 2d Th 9c 9h> ==><0=cid, Jh 4c 5c 2d Th 9c 9h=player cards>
    local value = {}
    local player_id = table.remove(snap_value, 1)
    value.player_id = player_id

    -- snap_value[2] is reserved
    local cards = snap_value
    value.cards = cards

    return value
end

local _snapHandler = {
    [Constants.Snap.SnapType.SnapGameState]           = _handleGameState,
    [Constants.Snap.SnapType.SnapTable]               = _handleTable,
    [Constants.Snap.SnapType.SnapCards]               = _handleCards,
    [Constants.Snap.SnapType.SnapWinAmount]           = _handleWinAmount,
    [Constants.Snap.SnapType.SnapWinPot]              = _handleWinPot,
    [Constants.Snap.SnapType.SnapOddChips]            = _handleOddChips,
    [Constants.Snap.SnapType.SnapPlayerAction]        = _handlePlayerAction,
    [Constants.Snap.SnapType.SnapPlayerCurrent]       = _handlePlayerCurrent,
    [Constants.Snap.SnapType.SnapPlayerShow]          = _handlePlayerShow
}
Snap.snapHandler = _snapHandler

function Snap:handleSNAP(parts, args)
    if tonumber(parts[1]) ~= nil then
        table.remove(parts, 1)
    end

    local result = {state_type = "snap_state", data = {}}

    --tcp: SNAP 1:0 1 <1>   ---SNAP game_id:table_id snap_type snap_value
    local game_table = string_split(parts[2], ":")
    result.data.game_id = game_table[1]
    result.data.table_id = game_table[2]
    local snap_type = parts[3]
    result.data.snap_type = snap_type

    if not self.snapHandler[tonumber(snap_type)] then
        result.data.state = 3
        result.data.msg = "unknown snap type: " .. snap_type
        return result
    end

    args.game_id = result.data.game_id
    args.table_id = result.data.table_id
    result.data.snap_value = self.snapHandler[tonumber(snap_type)](table.subrange(parts, 4, #parts), args)

    return result
end

return Snap
