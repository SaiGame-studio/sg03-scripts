require "lib_battle_common"
require "lib_battle_ai"

-- alpha_turn_end.lua
-- End-of-turn cleanup for Alpha's turn.

local function handoff_lamp_to_omega(state)
    if state.client_actions == nil then state.client_actions = {} end
    lib_battle_common.append_client_action(state, "omega_take_lamp")
end

local function run_omega_draw(state)
    local omega_draw_count = lib_battle_common.get_draw_card_count()
    output.omega_draw_card_count = omega_draw_count

    local omega_new_hand, omega_draw_err = lib_battle_ai.omega_draw(state, omega_draw_count)
    if omega_draw_err ~= nil then return omega_draw_err end
    state.omega_hand = omega_new_hand
    return nil
end

local function run_omega_deploy(state)
    local ai_difficulty = state.metadata ~= nil and state.metadata.battle_difficulty or "normal"
    local o_front, o_back, o_hand, ai_err = lib_battle_ai.deploy_omega_cards(state, ai_difficulty)
    if ai_err ~= nil then return ai_err end
    state.omega_front_line = o_front
    state.omega_back_line  = o_back
    state.omega_hand       = o_hand
    return nil
end

local function run_omega_attack_planning(state)
    local attack_plan_err = lib_battle_ai.omega_planning_to_attack(state)
    if attack_plan_err ~= nil then return attack_plan_err end
    return nil
end

local function advance_turn_to_omega(state)
    if state.metadata == nil then state.metadata = {} end
    state.metadata.next_move = "omega_turn"
    state.turn = (state.turn or 0) + 1
    lib_battle_common.dlog("[alpha_turn_end] turn advanced to " .. tostring(state.turn) .. ", next_move = omega_turn")
    lib_battle_common.append_client_action(state, "alpha_take_lamp")
end

local function persist_battle_state(session_id, state)
    local save_err = game.battle_session_update(session_id, state)
    if save_err ~= nil then return save_err end
    lib_battle_common.dlog("[alpha_turn_end] session persisted")
    return nil
end

local function main()
    local session_id, sid_err = lib_battle_common.resolve_session_id()
    if sid_err ~= nil then output.error = sid_err ; return end

    local state, state_err = lib_battle_common.load_session(session_id)
    if state_err ~= nil then output.error = state_err ; return end
    lib_battle_common.dlog("[alpha_turn_end] session loaded: " .. session_id)

    lib_battle_common.reset_turn_cards(state)
    handoff_lamp_to_omega(state)

    local draw_err = run_omega_draw(state)
    if draw_err ~= nil then output.error = draw_err ; return end

    local deploy_err = run_omega_deploy(state)
    if deploy_err ~= nil then output.error = deploy_err ; return end

    local plan_err = run_omega_attack_planning(state)
    if plan_err ~= nil then output.error = plan_err ; return end

    advance_turn_to_omega(state)

    local save_err = persist_battle_state(session_id, state)
    if save_err ~= nil then output.error = save_err ; return end

    lib_battle_common.battle_status()
end

main()