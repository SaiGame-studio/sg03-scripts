require "lib_battle_common"
require "lib_ability_core"
require "lib_battle_entity_ai"
require "enemy_ai_goblin_shaman"
require "lib_ability_all"

local apply_attack            -- forward declaration
local commit_attack_result    -- forward declaration
-- on_attack behavior through the shared battle helpers.
-- Accumulated damage is stored directly on the card object inside the session state.
-- If total_damage_received exceeds the defender's final_def, the card is defeated
-- and moved to the_void of its side.
--
-- Payload schema:
--   session_id                  (string, optional)  battle session UUID; omit to use active session
--   attacker_inventory_item_id  (string)  UUID of the acting card instance
--   defender_inventory_item_id  (string)  UUID of the target card instance

-- ---------------------------------------------------------------------------
-- Helpers
-- ---------------------------------------------------------------------------

local function validate_payload()
    if not payload.attacker_inventory_item_id or payload.attacker_inventory_item_id == "" then
        return "missing attacker_inventory_item_id"
    end
    if not payload.defender_inventory_item_id or payload.defender_inventory_item_id == "" then
        return "missing defender_inventory_item_id"
    end
    return nil
end

local function find_item_def(item_defs, code)
    if item_defs == nil then return nil end
    for _, item_def in ipairs(item_defs) do
        if item_def.item_code == code then return item_def end
    end
    return nil
end

-- Searches all four battle lines and returns the first card matching inventory_item_id.
-- Returns: card, line_key, side_void - or nil, nil, nil if not found.
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
    return {
        { line = state.alpha_front_line or {}, line_key = "alpha_front_line", side_void = "alpha_the_void" },
        { line = state.alpha_back_line  or {}, line_key = "alpha_back_line",  side_void = "alpha_the_void" },
        { line = state.omega_front_line or {}, line_key = "omega_front_line", side_void = "omega_the_void" },
        { line = state.omega_back_line  or {}, line_key = "omega_back_line",  side_void = "omega_the_void" },
    }
end

local function build_named_zones(state)
    local named_zones = build_named_lines(state)
    table.insert(named_zones, { line = state.alpha_hand or {},       line_key = "alpha_hand",       side_void = nil })
    table.insert(named_zones, { line = state.omega_hand or {},       line_key = "omega_hand",       side_void = nil })
    table.insert(named_zones, { line = state.alpha_the_void or {},   line_key = "alpha_the_void",   side_void = "alpha_the_void" })
    table.insert(named_zones, { line = state.omega_the_void or {},   line_key = "omega_the_void",   side_void = "omega_the_void" })
    table.insert(named_zones, { line = state.alpha_the_source or {}, line_key = "alpha_the_source", side_void = nil })
    table.insert(named_zones, { line = state.omega_the_source or {}, line_key = "omega_the_source", side_void = nil })
    return named_zones
end

-- Locates attacker and defender cards across all battle lines in the given state.
-- Returns: attacker_card, attacker_line_key, defender_card, defender_line_key, defender_side_void
local function resolve_cards(state)
    local named_lines = build_named_lines(state)
    local attacker_card, attacker_line_key = find_card_in_lines(named_lines, payload.attacker_inventory_item_id)
    local defender_card, defender_line_key, defender_side_void = find_card_in_lines(named_lines, payload.defender_inventory_item_id)
    return attacker_card, attacker_line_key, defender_card, defender_line_key, defender_side_void
end

-- Looks up item definitions for both cards from state.item_defs.
-- Returns: attacker_def, defender_def, err
local function resolve_item_defs(state, attacker_card, defender_card)
    local atk_code = attacker_card.item_definition_code_name
    local def_code = defender_card.item_definition_code_name
    if not atk_code or atk_code == "" then
        return nil, nil, "attacker card has no item_definition_code_name"
    end
    if not def_code or def_code == "" then
        return nil, nil, "defender card has no item_definition_code_name"
    end
    local attacker_def = find_item_def(state.item_defs, atk_code)
    local defender_def = find_item_def(state.item_defs, def_code)
    if attacker_def == nil then return nil, nil, "item def not found in state.item_defs: " .. atk_code end
    if defender_def == nil then return nil, nil, "item def not found in state.item_defs: " .. def_code end
    return attacker_def, defender_def, nil
end

local function log_card_info(attacker_card, defender_card, attacker_def, defender_def, defender_line_key, defender_side_void)
    local attacker_base_atk = (attacker_def.base_stats and attacker_def.base_stats.atk) or 0
    local defender_base_def = (defender_def.base_stats and defender_def.base_stats.def) or 0
    lib_battle_common.dlog("attacker: id=" .. attacker_card.inventory_item_id .. " code=" .. attacker_card.item_definition_code_name .. " base_atk=" .. attacker_base_atk)
    lib_battle_common.dlog("defender: id=" .. defender_card.inventory_item_id .. " code=" .. defender_card.item_definition_code_name .. " base_def=" .. defender_base_def)
    lib_battle_common.dlog("defender_line=" .. defender_line_key .. " side_void=" .. defender_side_void)
end

-- Computes final damage dealt by the attacker
local function compute_damage(attacker_def)
    local base_atk = 0
    if attacker_def.base_stats ~= nil and attacker_def.base_stats.atk then
        base_atk = attacker_def.base_stats.atk
    elseif attacker_def.metadata ~= nil and attacker_def.metadata.atk then
        base_atk = attacker_def.metadata.atk
    end
    local damage_dealt = base_atk
    lib_battle_common.dlog("[alpha_card_active] compute_damage: base_atk=" .. base_atk .. " damage_dealt(debug override)=" .. damage_dealt)
    return damage_dealt
end

local function log_defender_status(defender_card)
    local total_dmg     = defender_card.total_damage_received or 0
    local final_def_val = defender_card.final_def or 0
    local defeated_str  = total_dmg >= final_def_val and "yes" or "no"
    lib_battle_common.dlog("defender.total_damage_received=" .. total_dmg .. " final_def=" .. final_def_val .. " defeated=" .. defeated_str)
end

-- Resolves attacker card only (no defender card required).
-- Returns: attacker_card, attacker_line_key, attacker_def, err
local function resolve_attacker_context(state)
    local named_lines = build_named_lines(state)
    local attacker_card, attacker_line_key = find_card_in_lines(named_lines, payload.attacker_inventory_item_id)
    if attacker_card == nil then return nil, nil, nil, "attacker card not found in any battle line" end
    if attacker_card.trigger == true then return nil, nil, nil, "attacker card has already attacked this turn" end

    local atk_code = attacker_card.item_definition_code_name
    if not atk_code or atk_code == "" then return nil, nil, nil, "attacker card has no item_definition_code_name" end
    local attacker_def = find_item_def(state.item_defs, atk_code)
    if attacker_def == nil then return nil, nil, nil, "item def not found in state.item_defs: " .. atk_code end

    return attacker_card, attacker_line_key, attacker_def, nil
end

local function resolve_defender_anywhere(state)
    return find_card_in_lines(build_named_zones(state), payload.defender_inventory_item_id)
end

local function resolve_pending_defender(state, pending_atk)
    if pending_atk == nil or pending_atk.defender_inventory_item_id == nil or pending_atk.defender_inventory_item_id == "" then
        return nil, nil, nil
    end
    return find_card_in_lines(build_named_lines(state), pending_atk.defender_inventory_item_id)
end

-- Resolves cards & defs, validates action preconditions.
-- Returns: attacker_card, attacker_line_key, attacker_def,
--          defender_card, defender_line_key, defender_side_void, defender_def, err
local function resolve_attack_context(state)
    local attacker_card, attacker_line_key = find_card_in_lines(build_named_lines(state), payload.attacker_inventory_item_id)
    if attacker_card == nil then return nil, nil, nil, nil, nil, nil, nil, "attacker card not found in any battle line" end
    if attacker_card.trigger == true then return nil, nil, nil, nil, nil, nil, nil, "attacker card has already attacked this turn" end

    local defender_card, defender_line_key, defender_side_void = resolve_defender_anywhere(state)
    if defender_card == nil then return nil, nil, nil, nil, nil, nil, nil, "defender card not found in battle state" end

    local attacker_def, defender_def, def_err = resolve_item_defs(state, attacker_card, defender_card)
    if def_err ~= nil then return nil, nil, nil, nil, nil, nil, nil, def_err end

    return attacker_card, attacker_line_key, attacker_def,
           defender_card, defender_line_key, defender_side_void, defender_def, nil
end

local function activate_attack_ability(state,
    attacker_card, attacker_line_key, attacker_def,
    defender_card, defender_def, defender_line_key, defender_side_void)
    local attacker_type = attacker_def.metadata ~= nil and attacker_def.metadata.type or nil
    local allowed_ability_keys = {}
    if attacker_type == "ability" then
        table.insert(allowed_ability_keys, attacker_card.item_definition_code_name)
    else
        for _, ability_key in ipairs(lib_ability_core.get_ability_keys(attacker_card, state.item_defs)) do
            table.insert(allowed_ability_keys, ability_key)
        end
    end
    if #allowed_ability_keys == 0 then
        return "defender card is outside battle lines and attacker has no attack ability"
    end

    local can_target = false
    local target_position = nil
    for _, ability_key in ipairs(allowed_ability_keys) do
        local allowed, allowed_info = lib_ability_core.can_ability_target_position(
            state,
            attacker_card,
            ability_key,
            defender_line_key
        )
        if allowed then
            can_target = true
            break
        end
        target_position = allowed_info
    end
    if not can_target then
        return "target position is not allowed for this ability: " .. tostring(target_position)
    end

    lib_battle_common.dlog("[alpha_card_active] == phase 2: ability-only target ==")
    local event_data = {}
    event_data.defender_card      = defender_card
    event_data.damage_dealt       = 0
    event_data.attacker_def       = attacker_def
    event_data.defender_def       = defender_def
    event_data.defender_line_key  = defender_line_key
    event_data.defender_side_void = defender_side_void

    local ability_actions
    local ability_err
    if attacker_type == "ability" then
        ability_actions, ability_err = lib_ability_core.trigger_ability_by_key(
            state,
            attacker_card,
            attacker_card.item_definition_code_name,
            "on_attack",
            event_data
        )
    else
        ability_actions, ability_err = lib_ability_core.trigger_card_ability(
            state,
            attacker_card,
            "on_attack",
            event_data
        )
    end
    if ability_err ~= nil then return ability_err end

    attacker_card.trigger = true
    for _, action in ipairs(ability_actions or {}) do
        lib_battle_common.append_client_action(state, action)
    end
    return nil
end

-- Dispatches to the enemy-specific defending function after alpha's card action is planned.
-- Returns err or nil.
run_enemy_defend = function(session_id, state)
    lib_battle_common.dlog("[alpha_card_active] == phase 2: omega defending ==")
    local enemy_key = state.metadata ~= nil and state.metadata.enemy_entity_key or nil
    lib_battle_common.dlog("[alpha_card_active] enemy_entity_key=" .. tostring(enemy_key))
    return lib_battle_entity_ai.run_defend(state)
end

-- Phase 1: compute planned damage and store in state.pending_attack.
-- Omega can read/modify state.pending_attack during phase 2 before damage is applied.
local function plan_alpha_attack(state,
    attacker_card, attacker_def,
    defender_card, defender_def, defender_line_key, defender_side_void)
    lib_battle_common.dlog("[alpha_card_active] == phase 1: planning action ==")
    log_card_info(attacker_card, defender_card, attacker_def, defender_def, defender_line_key, defender_side_void)
    local damage_dealt = compute_damage(attacker_def)
    lib_battle_common.dlog("[alpha_card_active] planned damage_dealt=" .. damage_dealt)
    local pending_atk = {}
    pending_atk.attacker_inventory_item_id = attacker_card.inventory_item_id
    pending_atk.defender_inventory_item_id = defender_card.inventory_item_id
    pending_atk.damage_dealt               = damage_dealt
    state.pending_attack = pending_atk
    lib_battle_common.dlog("[alpha_card_active] pending_attack stored: attacker=" .. pending_atk.attacker_inventory_item_id .. " defender=" .. pending_atk.defender_inventory_item_id)
end

-- Phase 3: apply the (possibly modified) pending_attack onto the defender card.
-- Returns err or nil.
local function resolve_alpha_attack(state,
    attacker_card, attacker_line_key, attacker_def,
    defender_card, defender_def, defender_line_key, defender_side_void)
    lib_battle_common.dlog("[alpha_card_active] == phase 3: resolving action ==")
    local pending_atk  = state.pending_attack
    local final_damage = pending_atk ~= nil and pending_atk.damage_dealt or 0
    local live_defender_card, live_defender_line_key, live_defender_side_void = resolve_pending_defender(state, pending_atk)
    if live_defender_card == nil then
        lib_battle_common.dlog("[alpha_card_active] defender no longer on field, skipping resolve: " .. tostring(pending_atk ~= nil and pending_atk.defender_inventory_item_id or nil))
        state.pending_attack = nil
        attacker_card.trigger = true
        attacker_card.face_up = true
        attacker_card.expose  = true
        lib_battle_common.append_client_action(state, "alpha_card_expose:" .. attacker_card.inventory_item_id)
        return nil
    end
    lib_battle_common.dlog("[alpha_card_active] final_damage=" .. final_damage)
    local attack_err = lib_battle_common.card_attack_card(
        state,
        attacker_card, attacker_def, attacker_line_key,
        live_defender_card, defender_def, live_defender_line_key, live_defender_side_void,
        final_damage
    )
    if attack_err ~= nil then return attack_err end
    state.pending_attack = nil
    log_defender_status(live_defender_card)
    return nil
end

-- Orchestrates all 3 phases: plan -> omega defend -> resolve.
-- Returns err or nil.
apply_attack = function(session_id, state,
    attacker_card, attacker_line_key, attacker_def,
    defender_card, defender_line_key, defender_side_void, defender_def)
    lib_battle_common.dlog("session_id=" .. session_id)
    plan_alpha_attack(state,
        attacker_card, attacker_def,
        defender_card, defender_def, defender_line_key, defender_side_void)
    local defend_err = run_enemy_defend(session_id, state)
    if defend_err ~= nil then return defend_err end
    local resolve_err = resolve_alpha_attack(state,
        attacker_card, attacker_line_key, attacker_def,
        defender_card, defender_def, defender_line_key, defender_side_void)
    if resolve_err ~= nil then return resolve_err end
    return nil
end

-- Increments action counter, saves session, and calls battle_status.
-- Returns err or nil.
commit_attack_result = function(session_id, state, is_development)
    state.action     = (state.action or 0) + 1
    state.updated_at = ctx.timestamp
    local save_err = game.battle_session_update(session_id, state)
    if save_err ~= nil then return "failed to save battle state: " .. save_err end
    if is_development then
        lib_battle_common.dlog("total client_actions=" .. #state.client_actions)
    end
    lib_battle_common.battle_status()
    return nil
end

-- Applies attacker damage directly to omega_hp.
-- Returns err or nil.
local function attack_omega_hp(session_id, state, attacker_card, attacker_def, is_development)
    if not lib_battle_common.check_card_type(state.item_defs, attacker_card, "character") then
        return "attacker is not a character"
    end
    for _, card in ipairs(state.omega_front_line or {}) do
        if card.inventory_item_id ~= nil and card.inventory_item_id ~= "" then
            return "cannot attack omega while omega front line still has cards"
        end
    end
    local damage = compute_damage(attacker_def)
    lib_battle_common.dlog("[alpha_card_active] attacking omega_hp directly: damage=" .. damage)
    state.omega_hp = (state.omega_hp or 0) - damage
    lib_battle_common.dlog("[alpha_card_active] omega_hp after attack=" .. state.omega_hp)
    attacker_card.trigger  = true
    attacker_card.face_up  = true
    attacker_card.expose   = true
    lib_battle_common.append_client_action(state, "alpha_card_expose:" .. attacker_card.inventory_item_id)
    lib_battle_common.append_client_action(state, "alpha_attack_omega_hp:attacker_card_id=" .. attacker_card.inventory_item_id .. ",damage=" .. damage .. ",omega_hp=" .. state.omega_hp)
    local omega_defeated = state.omega_hp <= 0
    if omega_defeated then
        lib_battle_common.append_client_action(state, "battle_completed:alpha")
        state.status = "completed"
    end
    local commit_err = commit_attack_result(session_id, state, is_development)
    if commit_err ~= nil then return commit_err end
    return nil
end

-- Main

local function main()
    local payload_err = validate_payload()
    if payload_err ~= nil then output.error = payload_err ; return end

    local is_development = ctx.game ~= nil and ctx.game.status == "development"

    local session_id, session_err = lib_battle_common.resolve_session_id()
    if session_err ~= nil then output.error = session_err ; return end
    if session_id == nil then output.error = "failed to resolve session_id" ; return end

    local state, state_err = lib_battle_common.load_session(session_id)
    if state_err ~= nil then output.error = state_err ; return end
    if state.status == "completed" then output.error = "battle is already completed" ; return end

    if payload.defender_inventory_item_id == "alpha" or payload.defender_inventory_item_id == "omega" or payload.defender_inventory_item_id == "omega_hp" then
        local attacker_card, attacker_line_key, attacker_def, ctx_err = resolve_attacker_context(state)
        if ctx_err ~= nil then output.error = ctx_err ; return end

        local attacker_type = attacker_def.metadata ~= nil and attacker_def.metadata.type or nil
        local is_spell_ability = (attacker_type == "ability")

        if is_spell_ability then
            local possible_lines
            if payload.defender_inventory_item_id == "alpha" then
                possible_lines = { "alpha_the_source", "alpha_front_line", "alpha_back_line" }
            else
                possible_lines = { "omega_the_source", "omega_front_line", "omega_back_line" }
            end

            local resolved_line_key = nil
            local allowed_keys = {}
            if attacker_type == "ability" then
                table.insert(allowed_keys, attacker_card.item_definition_code_name)
            else
                for _, k in ipairs(lib_ability_core.get_ability_keys(attacker_card, state.item_defs)) do
                    table.insert(allowed_keys, k)
                end
            end

            for _, line_key in ipairs(possible_lines) do
                for _, ability_key in ipairs(allowed_keys) do
                    local allowed = lib_ability_core.can_ability_target_position(state, attacker_card, ability_key, line_key)
                    if allowed then
                        resolved_line_key = line_key
                        break
                    end
                end
                if resolved_line_key then break end
            end

            if resolved_line_key == nil then
                resolved_line_key = possible_lines[1]
            end

            local ability_err = activate_attack_ability(
                state,
                attacker_card, attacker_line_key, attacker_def,
                nil, nil, resolved_line_key, nil
            )
            if ability_err ~= nil then output.error = ability_err ; return end
            local commit_err = commit_attack_result(session_id, state, is_development)
            if commit_err ~= nil then output.error = commit_err ; return end
            return
        else
            if payload.defender_inventory_item_id == "alpha" then
                output.error = "cannot attack own hp"
                return
            end

            local attack_err = attack_omega_hp(session_id, state, attacker_card, attacker_def, is_development)
            if attack_err ~= nil then output.error = attack_err ; return end
            return
        end
    end

    local attacker_card, attacker_line_key, attacker_def,
          defender_card, defender_line_key, defender_side_void, defender_def,
          ctx_err = resolve_attack_context(state)
    if ctx_err ~= nil then output.error = ctx_err ; return end

    local target_is_on_battle_line =
        defender_line_key == "alpha_front_line" or
        defender_line_key == "alpha_back_line"  or
        defender_line_key == "omega_front_line" or
        defender_line_key == "omega_back_line"

    if not target_is_on_battle_line then
        local ability_err = activate_attack_ability(
            state,
            attacker_card, attacker_line_key, attacker_def,
            defender_card, defender_def, defender_line_key, defender_side_void
        )
        if ability_err ~= nil then output.error = ability_err ; return end
        local commit_err = commit_attack_result(session_id, state, is_development)
        if commit_err ~= nil then output.error = commit_err ; return end
        return
    end

    local attack_err = apply_attack(
        session_id, state,
        attacker_card, attacker_line_key, attacker_def,
        defender_card, defender_line_key, defender_side_void, defender_def
    )
    if attack_err ~= nil then output.error = attack_err ; return end

    local commit_err = commit_attack_result(session_id, state, is_development)
    if commit_err ~= nil then output.error = commit_err ; return end
end

main()
