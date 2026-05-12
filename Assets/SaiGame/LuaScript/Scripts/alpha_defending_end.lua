require "lib_battle_common"
require "lib_card_ability"

-- alpha_defending_end.lua
-- Ends Alpha's defending phase by executing the queued Omega plan entries
-- (`state.omega_planning`) in order. Each entry describes one Omega action
-- (currently `card_attack_card`) planned during `alpha_turn_end`.
--
-- Payload schema:
--   session_id (string, optional)  battle session UUID; omit to use active session

-- ---------------------------------------------------------------------------
-- Helpers
-- ---------------------------------------------------------------------------

local function resolve_session_id()
    if payload.session_id ~= nil and payload.session_id ~= "" then
        return payload.session_id, nil
    end
    local sid, sid_err = game.battle_session_current_id()
    if sid_err ~= nil then return nil, sid_err end
    if sid == nil or sid == "" then return nil, "no active battle session" end
    return sid, nil
end

local function find_item_def(item_defs, code)
    if item_defs == nil then return nil end
    for _, item_def in ipairs(item_defs) do
        if item_def.item_code == code then return item_def end
    end
    return nil
end

-- Returns: card, line_key, side_void — or nil, nil, nil if not found.
local function find_card_in_lines(named_lines, inventory_item_id)
    for _, entry in ipairs(named_lines) do
        for _, slot_card in ipairs(entry.line) do
            if slot_card.inventory_item_id == inventory_item_id then
                return slot_card, entry.line_key, entry.side_void
            end
        end
    end
    return nil, nil, nil
end

local function build_named_lines(state)
    local named_lines = {}
    local alpha_front = {}
    alpha_front.line      = state.alpha_front_line or {}
    alpha_front.line_key  = "alpha_front_line"
    alpha_front.side_void = "alpha_the_void"
    local alpha_back = {}
    alpha_back.line       = state.alpha_back_line or {}
    alpha_back.line_key   = "alpha_back_line"
    alpha_back.side_void  = "alpha_the_void"
    local omega_front = {}
    omega_front.line      = state.omega_front_line or {}
    omega_front.line_key  = "omega_front_line"
    omega_front.side_void = "omega_the_void"
    local omega_back = {}
    omega_back.line       = state.omega_back_line or {}
    omega_back.line_key   = "omega_back_line"
    omega_back.side_void  = "omega_the_void"
    table.insert(named_lines, alpha_front)
    table.insert(named_lines, alpha_back)
    table.insert(named_lines, omega_front)
    table.insert(named_lines, omega_back)
    return named_lines
end

-- Resolves attacker/defender cards, line keys and item defs for one plan entry.
local function resolve_attack_plan(state, plan_entry)
    local named_lines = build_named_lines(state)

    local attacker_card, attacker_line_key = find_card_in_lines(named_lines, plan_entry.attacker_inv_id)
    if attacker_card == nil then
        return nil, "attacker card not found: " .. tostring(plan_entry.attacker_inv_id)
    end

    local defender_card, defender_line_key, defender_side_void = find_card_in_lines(named_lines, plan_entry.defender_inv_id)
    if defender_card == nil then
        return nil, "defender card not found: " .. tostring(plan_entry.defender_inv_id)
    end

    local attacker_def = find_item_def(state.item_defs, attacker_card.item_definition_code_name)
    if attacker_def == nil then
        return nil, "attacker item def not found: " .. tostring(attacker_card.item_definition_code_name)
    end
    local defender_def = find_item_def(state.item_defs, defender_card.item_definition_code_name)
    if defender_def == nil then
        return nil, "defender item def not found: " .. tostring(defender_card.item_definition_code_name)
    end

    local resolved = {}
    resolved.attacker_card      = attacker_card
    resolved.attacker_line_key  = attacker_line_key
    resolved.attacker_def       = attacker_def
    resolved.defender_card      = defender_card
    resolved.defender_line_key  = defender_line_key
    resolved.defender_side_void = defender_side_void
    resolved.defender_def       = defender_def
    return resolved, nil
end

local function compute_attack_damage(attacker_def)
    return (attacker_def.base_stats and attacker_def.base_stats.atk) or 0
end

local function execute_card_attack_plan(state, plan_entry)
    local resolved, resolve_err = resolve_attack_plan(state, plan_entry)
    if resolve_err ~= nil then return resolve_err end

    if resolved.attacker_card.trigger == true then
        lib_battle_common.dlog("[alpha_defending_end] attacker already triggered, skipping: " .. resolved.attacker_card.inventory_item_id)
        return nil
    end

    local damage_dealt = compute_attack_damage(resolved.attacker_def)
    lib_battle_common.dlog("[alpha_defending_end] executing card_attack_card damage=" .. tostring(damage_dealt))

    local attack_err = lib_battle_common.card_attack_card(
        state,
        resolved.attacker_card, resolved.attacker_def, resolved.attacker_line_key,
        resolved.defender_card, resolved.defender_def, resolved.defender_line_key, resolved.defender_side_void,
        damage_dealt
    )
    if attack_err ~= nil then return attack_err end

    -- Animate attacker returning to its slot on the client.
    local attacker_side = (string.sub(resolved.attacker_line_key, 1, 5) == "alpha") and "alpha" or "omega"
    lib_battle_common.append_client_action(state, attacker_side .. "_card_move_back_to_holder:" .. resolved.attacker_card.inventory_item_id)

    return nil
end

local function execute_plan_entry(state, plan_entry)
    if type(plan_entry) ~= "table" or plan_entry.action == nil then
        return "invalid omega_planning entry"
    end
    if plan_entry.action == "card_attack_card" then
        return execute_card_attack_plan(state, plan_entry)
    end
    return "unsupported omega_planning action: " .. tostring(plan_entry.action)
end

local function execute_omega_planning(state)
    local planning = state.omega_planning or {}
    lib_battle_common.dlog("[alpha_defending_end] executing " .. tostring(#planning) .. " plan entries")
    for plan_index, plan_entry in ipairs(planning) do
        local exec_err = execute_plan_entry(state, plan_entry)
        if exec_err ~= nil then
            return "plan[" .. tostring(plan_index) .. "]: " .. exec_err
        end
    end
    return nil
end

-- ---------------------------------------------------------------------------
-- Main
-- ---------------------------------------------------------------------------

local function main()
    local session_id, session_err = resolve_session_id()
    if session_err ~= nil then output.error = session_err ; return end

    local state, state_err = game.battle_session_get(session_id)
    if state_err ~= nil then output.error = state_err ; return end
    if state == nil then output.error = "battle session not found" ; return end
    lib_battle_common.dlog("[alpha_defending_end] session loaded: " .. session_id)

    local plan_err = execute_omega_planning(state)
    if plan_err ~= nil then output.error = plan_err ; return end

    -- ── Clear planning queue and exit defending phase ─────────────────────
    state.omega_planning  = {}
    state.alpha_defending = false

    state.action     = (state.action or 0) + 1
    state.updated_at = ctx.timestamp

    local save_err = game.battle_session_update(session_id, state)
    if save_err ~= nil then output.error = "failed to save battle state: " .. save_err ; return end

    lib_battle_common.battle_status()
end

main()