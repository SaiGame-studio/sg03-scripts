require "lib_battle_common"
require "lib_card_ability"

-- alpha_attacking.lua
-- Applies attacker's base_atk as damage onto the defender card in the battle state.
-- Accumulated damage is stored directly on the card object inside the session state.
-- If total_damage_received exceeds the defender's final_def, the card is defeated
-- and moved to the_void of its side.
--
-- Payload schema:
--   session_id                  (string, optional)  battle session UUID; omit to use active session
--   attacker_inventory_item_id  (string)  UUID of the attacking card instance
--   defender_inventory_item_id  (string)  UUID of the defending card instance

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

-- Locates attacker and defender cards across all battle lines in the given state.
-- Returns: attacker_card, attacker_line_key, defender_card, defender_line_key, defender_side_void
local function resolve_cards(state)
    local named_lines = {
        { line = state.alpha_front_line or {}, line_key = "alpha_front_line", side_void = "alpha_the_void" },
        { line = state.alpha_back_line  or {}, line_key = "alpha_back_line",  side_void = "alpha_the_void" },
        { line = state.omega_front_line or {}, line_key = "omega_front_line", side_void = "omega_the_void" },
        { line = state.omega_back_line  or {}, line_key = "omega_back_line",  side_void = "omega_the_void" },
    }
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

-- Computes final damage dealt by the attacker (includes debug override).
local function compute_damage(is_development, attacker_def)
    local base_atk     = (attacker_def.base_stats and attacker_def.base_stats.atk) or 0
    local damage_dealt = base_atk
    damage_dealt = 10  -- To debug
    if is_development then
        lib_battle_common.dlog("base_atk=" .. base_atk .. " | damage_dealt (debug override)=" .. damage_dealt)
    end
    return damage_dealt
end

local function log_defender_status(defender_card)
    local total_dmg     = defender_card.total_damage_received or 0
    local final_def_val = defender_card.final_def or 0
    local defeated_str  = total_dmg > final_def_val and "yes" or "no"
    lib_battle_common.dlog("defender.total_damage_received=" .. total_dmg .. " final_def=" .. final_def_val .. " defeated=" .. defeated_str)
end

-- Loads battle state, resolves cards & defs, validates attack preconditions.
-- Returns: session_id, state, attacker_card, attacker_line_key, attacker_def,
--          defender_card, defender_line_key, defender_side_void, defender_def, err
local function load_attack_context()
    local session_id, session_err = lib_battle_common.resolve_session_id()
    if session_err ~= nil then return nil, nil, nil, nil, nil, nil, nil, nil, nil, session_err end
    if session_id == nil then return nil, nil, nil, nil, nil, nil, nil, nil, nil, "failed to resolve session_id" end

    local state, state_err = lib_battle_common.load_session(session_id)
    if state_err ~= nil then return nil, nil, nil, nil, nil, nil, nil, nil, nil, state_err end

    local attacker_card, attacker_line_key, defender_card, defender_line_key, defender_side_void = resolve_cards(state)
    if attacker_card == nil then return nil, nil, nil, nil, nil, nil, nil, nil, nil, "attacker card not found in any battle line" end
    if attacker_card.trigger == true then return nil, nil, nil, nil, nil, nil, nil, nil, nil, "attacker card has already attacked this turn" end
    if defender_card == nil then return nil, nil, nil, nil, nil, nil, nil, nil, nil, "defender card not found in any battle line" end

    local attacker_def, defender_def, def_err = resolve_item_defs(state, attacker_card, defender_card)
    if def_err ~= nil then return nil, nil, nil, nil, nil, nil, nil, nil, nil, def_err end

    return session_id, state, attacker_card, attacker_line_key, attacker_def,
           defender_card, defender_line_key, defender_side_void, defender_def, nil
end

-- ---------------------------------------------------------------------------
-- Main
-- ---------------------------------------------------------------------------

local function main()
    local payload_err = validate_payload()
    if payload_err ~= nil then output.error = payload_err ; return end

    local session_id, state,
          attacker_card, attacker_line_key, attacker_def,
          defender_card, defender_line_key, defender_side_void, defender_def,
          ctx_err = load_attack_context()
    if ctx_err ~= nil then output.error = ctx_err ; return end
    if session_id == nil or state == nil then output.error = "failed to load attack context" ; return end

    local is_development = ctx.game ~= nil and ctx.game.status == "development"
    lib_battle_common.dlog("session_id=" .. session_id)
    if is_development then
        log_card_info(attacker_card, defender_card, attacker_def, defender_def, defender_line_key, defender_side_void)
    end

    local damage_dealt = compute_damage(is_development, attacker_def)

    local attack_err = lib_battle_common.card_attack_card(
        state,
        attacker_card, attacker_def, attacker_line_key,
        defender_card, defender_def, defender_line_key, defender_side_void,
        damage_dealt
    )
    if attack_err ~= nil then output.error = attack_err ; return end

    if is_development then log_defender_status(defender_card) end

    state.action     = (state.action or 0) + 1
    state.updated_at = ctx.timestamp

    local save_err = game.battle_session_update(session_id, state)
    if save_err ~= nil then output.error = "failed to save battle state: " .. save_err ; return end

    if is_development then
        lib_battle_common.dlog("total client_actions=" .. #state.client_actions)
    end

    lib_battle_common.battle_status()
end

main()