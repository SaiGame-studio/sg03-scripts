require "lib_battle_common"
require "lib_battle_ai"
require "lib_battle_entity_ai"
require "enemy_ai_goblin_shaman"

-- alpha_turn_end.lua
-- End-of-turn cleanup for Alpha's turn.

local function gen_id()
    local t = "xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx"
    return string.gsub(t, "[xy]", function(c)
        local v = (c == "x") and math.random(0, 15) or math.random(8, 11)
        return string.format("%x", v)
    end)
end

local function handoff_lamp_to_omega(state)
    if state.client_actions == nil then state.client_actions = {} end
    lib_battle_common.append_client_action(state, "omega_take_lamp")
end

local function run_omega_draw(state)
    local hand_size        = lib_battle_common.get_hand_size()
    local omega_draw_count = lib_battle_common.get_draw_card_count()
    output.omega_draw_card_count = omega_draw_count

    local source = state.omega_the_source
    if source == nil then
        return "omega_the_source not found in session state"
    end

    -- Ensure hand is always a fixed-size array of hand_size slots
    if state.omega_hand == nil then state.omega_hand = {} end
    while #state.omega_hand < hand_size do
        table.insert(state.omega_hand, {})
    end

    math.randomseed(ctx.timestamp)

    local drawn = 0
    for i = 1, hand_size do
        if drawn >= omega_draw_count then break end
        if #source == 0 then break end
        local slot = state.omega_hand[i]
        -- slot is empty when it has no inventory_item_id
        if slot == nil or slot.inventory_item_id == nil or slot.inventory_item_id == "" then
            local idx  = math.random(1, #source)
            local card = source[idx]
            table.remove(source, idx)
            card.id                = gen_id()
            card.inventory_item_id = gen_id()
            card.slot_index        = i - 1
            card.trigger           = false
            card.stun_remain       = 0
            state.omega_hand[i]    = card
            lib_battle_common.append_client_action(state,
                "omega_source_to_hand:" .. card.inventory_item_id .. "," .. tostring(card.slot_index))
            drawn = drawn + 1
        end
    end

    lib_battle_common.dlog("[alpha_turn_end] run_omega_draw: drawn=" .. tostring(drawn))
    return nil
end

local function run_omega_attack_planning(state)
    local enemy_key = state.metadata ~= nil and state.metadata.enemy_entity_key or nil
    lib_battle_common.dlog("[alpha_turn_end] run_omega_attack_planning enemy_key=" .. tostring(enemy_key))
    local plan_err = lib_battle_entity_ai.run_plan_attack(state)
    if plan_err ~= nil then return plan_err end
    state.alpha_defending = true
    return nil
end

-- Dispatches to the enemy-specific deploy function by enemy_entity_key.
-- Returns err or nil.
local function run_omega_deploy(state)
    return lib_battle_entity_ai.deploy_enemy(state)
end

local function advance_turn_to_omega(state)
    if state.metadata == nil then state.metadata = {} end
    state.metadata.next_move = "omega_turn"
    lib_battle_common.append_client_action(state, "next_move:omega_turn")
    state.omega_defending = false
    state.turn = (state.turn or 0) + 1
    lib_battle_common.dlog("[alpha_turn_end] turn advanced to " .. tostring(state.turn) .. ", next_move = omega_turn, omega_defending=false")
    lib_battle_common.append_client_action(state, "alpha_take_lamp")
    lib_battle_common.append_client_action(state, "alpha_turn_end:" .. tostring(state.turn))
end

local function persist_battle_state(session_id, state)
    local save_err = game.battle_session_update(session_id, state)
    if save_err ~= nil then return save_err end
    lib_battle_common.dlog("[alpha_turn_end] session persisted")
    return nil
end

local function main()
    local session_id, sid_err = lib_battle_common.resolve_session_id()
    if sid_err ~= nil then
        output.error = sid_err; return
    end

    local state, state_err = lib_battle_common.load_session(session_id)
    if state_err ~= nil then
        output.error = state_err; return
    end
    if state.status == "completed" then output.error = "battle is already completed" ; return end
    lib_battle_common.dlog("[alpha_turn_end] session loaded: " .. session_id)

    lib_battle_common.reset_turn_cards(state)
    handoff_lamp_to_omega(state)

    local draw_err = run_omega_draw(state)
    if draw_err ~= nil then
        output.error = draw_err; return
    end

    local deploy_err = run_omega_deploy(state)
    if deploy_err ~= nil then
        output.error = deploy_err; return
    end

    local plan_err = run_omega_attack_planning(state)
    if plan_err ~= nil then
        output.error = plan_err; return
    end

    advance_turn_to_omega(state)

    local save_err = persist_battle_state(session_id, state)
    if save_err ~= nil then
        output.error = save_err; return
    end

    lib_battle_common.battle_status()
end

main()
