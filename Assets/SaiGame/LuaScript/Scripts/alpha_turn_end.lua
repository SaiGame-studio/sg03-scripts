require "lib_battle_common"
require "lib_battle_ai"
require "lib_battle_entity_ai"

-- alpha_turn_end.lua
-- End-of-turn cleanup for Alpha's turn.

local enemy_attack_planning_dispatch  -- table: enemy_entity_key → planning function
local plan_goblin_shaman              -- forward declaration

local function get_enemy_key(state)
    return state.metadata ~= nil and state.metadata.enemy_entity_key or nil
end

local function handoff_lamp_to_omega(state)
    if state.client_actions == nil then state.client_actions = {} end
    lib_battle_common.append_client_action(state, "omega_take_lamp")
end

local function run_omega_draw(state)
    local omega_draw_count = lib_battle_common.get_draw_card_count()
    output.omega_draw_card_count = omega_draw_count

    local omega_new_hand, omega_draw_err = lib_battle_ai.omega_draw_random(state, omega_draw_count)
    if omega_draw_err ~= nil then return omega_draw_err end
    state.omega_hand = omega_new_hand
    return nil
end

local function run_omega_attack_planning(state)
    local enemy_key = get_enemy_key(state)
    lib_battle_common.dlog("[alpha_turn_end] run_omega_attack_planning enemy_key=" .. tostring(enemy_key))
    local plan_fn = enemy_key ~= nil and enemy_attack_planning_dispatch[enemy_key] or nil
    if plan_fn == nil then
        return "no attack planning handler for enemy_entity_key: " .. tostring(enemy_key)
    end
    local plan_err = plan_fn(state)
    if plan_err ~= nil then return plan_err end
    state.alpha_defending = true
    return nil
end

-- ─── Enemy-specific mid-turn deploy functions ────────────────────────────────

-- Dispatches to the enemy-specific deploy function by enemy_entity_key.
-- Returns err or nil.
local function run_omega_deploy(state)
    return lib_battle_entity_ai.deploy_enemy(state)
end

plan_goblin_shaman = function(state)
    return lib_battle_entity_ai.goblin_shaman_plan_attack(state)
end

enemy_attack_planning_dispatch = {
    goblin_shaman = plan_goblin_shaman,
}

local function advance_turn_to_omega(state)
    if state.metadata == nil then state.metadata = {} end
    state.metadata.next_move = "omega_turn"
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
