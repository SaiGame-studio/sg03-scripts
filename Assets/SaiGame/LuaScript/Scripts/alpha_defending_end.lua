require "lib_battle_common"
require "lib_card_ability"
require "lib_battle_ai"
require "ability_twin_reaper"
require "ability_spinning_slash"
require "ability_cross_guard"
require "ability_totem_pulse"

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

-- Phase 1: store pending_attack so future alpha-defend reactions can read/modify it.
local function plan_omega_attack(state, resolved, damage_dealt)
    local pending_atk = {}
    pending_atk.attacker_inventory_item_id = resolved.attacker_card.inventory_item_id
    pending_atk.defender_inventory_item_id = resolved.defender_card.inventory_item_id
    pending_atk.damage_dealt               = damage_dealt
    state.pending_attack = pending_atk
    lib_battle_common.dlog("[alpha_defending_end] pending_attack stored: attacker=" .. pending_atk.attacker_inventory_item_id .. " defender=" .. pending_atk.defender_inventory_item_id .. " damage=" .. damage_dealt)
end

-- Phase 3: apply the (possibly modified) pending_attack damage.
local function resolve_omega_attack(state, resolved)
    local final_damage = state.pending_attack ~= nil and state.pending_attack.damage_dealt or 0
    lib_battle_common.dlog("[alpha_defending_end] resolve_omega_attack final_damage=" .. final_damage)
    local attack_err = lib_battle_common.card_attack_card(
        state,
        resolved.attacker_card, resolved.attacker_def, resolved.attacker_line_key,
        resolved.defender_card, resolved.defender_def, resolved.defender_line_key, resolved.defender_side_void,
        final_damage
    )
    if attack_err ~= nil then return attack_err end
    state.pending_attack = nil
    local attacker_side = (string.sub(resolved.attacker_line_key, 1, 5) == "alpha") and "alpha" or "omega"
    lib_battle_common.append_client_action(state, attacker_side .. "_card_move_back_to_holder:" .. resolved.attacker_card.inventory_item_id)
    return nil
end

local function execute_card_attack_plan(state, plan_entry)
    local resolved, resolve_err = resolve_attack_plan(state, plan_entry)
    if resolve_err ~= nil then
        if string.find(resolve_err, "attacker card not found", 1, true) then
            lib_battle_common.dlog("[alpha_defending_end] attacker no longer on field — alpha defending succeeded: " .. tostring(plan_entry.attacker_inv_id))
            return nil
        end
        return resolve_err
    end

    if resolved.attacker_card.trigger == true then
        lib_battle_common.dlog("[alpha_defending_end] attacker already triggered, skipping: " .. resolved.attacker_card.inventory_item_id)
        return nil
    end

    -- Phase 1: plan (stores pending_attack for potential alpha defend reactions).
    local damage_dealt = compute_attack_damage(resolved.attacker_def)
    plan_omega_attack(state, resolved, damage_dealt)

    -- Phase 2: (reserved for future alpha defend reactions).

    -- Phase 3: resolve using pending_attack.damage_dealt.
    local resolve_err2 = resolve_omega_attack(state, resolved)
    if resolve_err2 ~= nil then return resolve_err2 end

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
    local session_id, session_err = lib_battle_common.resolve_session_id()
    if session_err ~= nil then output.error = session_err ; return end

    local state, state_err = lib_battle_common.load_session(session_id)
    if state_err ~= nil then output.error = state_err ; return end
    if state.status == "completed" then output.error = "battle is already completed" ; return end
    lib_battle_common.dlog("[alpha_defending_end] session loaded: " .. session_id)

    local plan_err = execute_omega_planning(state)
    if plan_err ~= nil then output.error = plan_err ; return end

    -- ── Clear planning queue and exit defending phase ─────────────────────
    state.omega_planning  = {}

    -- ── Re-plan omega's next attack after executing this round's plan ─────
    local next_plan_err = lib_battle_ai.omega_planning_to_attack(state)
    if next_plan_err ~= nil then output.error = next_plan_err ; return end

    state.action     = (state.action or 0) + 1
    state.updated_at = ctx.timestamp

    local save_err = game.battle_session_update(session_id, state)
    if save_err ~= nil then output.error = "failed to save battle state: " .. save_err ; return end

    lib_battle_common.battle_status()
end

main()
