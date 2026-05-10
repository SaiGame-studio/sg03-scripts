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

local function expose_cards(attacker_card, defender_card)
    attacker_card.face_up = true
    attacker_card.expose  = true
    defender_card.face_up = true
    defender_card.expose  = true
end

-- Fires the appropriate on_attack ability for the attacker card.
-- Returns: actions, err
local function trigger_attacker_ability(state, attacker_card, attacker_def, defender_card, defender_def, defender_line_key, defender_side_void, damage_dealt)
    lib_battle_common.dlog("trigger on_attack: card=" .. attacker_card.inventory_item_id .. " code=" .. (attacker_card.item_definition_code_name or "?") .. " abilities=[" .. tostring(attacker_card.metadata ~= nil and attacker_card.metadata.abilities or "") .. "]")

    local atk_event_data = {}
    atk_event_data.defender_card      = defender_card
    atk_event_data.damage_dealt       = damage_dealt
    atk_event_data.attacker_def       = attacker_def
    atk_event_data.defender_def       = defender_def
    atk_event_data.defender_line_key  = defender_line_key
    atk_event_data.defender_side_void = defender_side_void

    if attacker_def.metadata ~= nil and attacker_def.metadata.type == "ability" then
        local ability_key = attacker_card.item_definition_code_name
        lib_battle_common.dlog("trigger on_attack: attacker is ability-type, using item_code as ability key: " .. tostring(ability_key))
        return lib_card_ability.trigger_ability_by_key(state, attacker_card, ability_key, "on_attack", atk_event_data)
    end
    return lib_card_ability.trigger_card_ability(state, attacker_card, "on_attack", atk_event_data)
end

-- Fires the on_damaged ability for the defender card.
-- Returns: actions, err
local function trigger_defender_ability(state, attacker_card, attacker_def, defender_card, defender_def, damage_dealt)
    lib_battle_common.dlog("trigger on_damaged: card=" .. defender_card.inventory_item_id .. " code=" .. (defender_card.item_definition_code_name or "?") .. " abilities=[" .. tostring(defender_card.metadata ~= nil and defender_card.metadata.abilities or "") .. "]")

    local def_event_data = {}
    def_event_data.attacker_card   = attacker_card
    def_event_data.damage_received = damage_dealt
    def_event_data.attacker_def    = attacker_def
    def_event_data.defender_def    = defender_def
    return lib_card_ability.trigger_card_ability(state, defender_card, "on_damaged", def_event_data)
end

local function append_client_actions(state, attacker_card, defender_card, defender_side_void, dmg_actions, atk_ability_actions, def_ability_actions)
    local attacker_side = "alpha"
    local defender_side = (defender_side_void == "alpha_the_void") and "alpha" or "omega"
    lib_battle_common.append_client_action(state, attacker_side .. "_card_expose:" .. attacker_card.inventory_item_id)
    lib_battle_common.append_client_action(state, defender_side .. "_card_expose:" .. defender_card.inventory_item_id)
    lib_battle_common.append_client_action(state, "alpha_attack:" .. payload.attacker_inventory_item_id .. "," .. payload.defender_inventory_item_id)
    for _, action in ipairs(dmg_actions) do lib_battle_common.append_client_action(state, action) end
    for _, action in ipairs(atk_ability_actions) do lib_battle_common.append_client_action(state, action) end
    for _, action in ipairs(def_ability_actions) do lib_battle_common.append_client_action(state, action) end
end

-- If the attacker is an ability-type card, remove it from its line and send it to alpha_the_void.
local function handle_ability_type_attacker(state, attacker_card, attacker_line_key, attacker_def)
    if attacker_def.metadata == nil or attacker_def.metadata.type ~= "ability" then return end
    lib_battle_common.remove_card_from_line(state[attacker_line_key], attacker_card.inventory_item_id)
    if state.alpha_the_void == nil then state.alpha_the_void = {} end
    table.insert(state.alpha_the_void, attacker_card)
    lib_battle_common.append_client_action(state, "alpha_card_sent_to_void:" .. attacker_card.inventory_item_id)
    lib_battle_common.dlog("attacker is ability-type, sent to alpha_the_void: " .. attacker_card.inventory_item_id)
end

-- ---------------------------------------------------------------------------
-- Main
-- ---------------------------------------------------------------------------

local function main()
    local payload_err = validate_payload()
    if payload_err ~= nil then output.error = payload_err ; return end

    local session_id, session_err = resolve_session_id()
    if session_err ~= nil then output.error = session_err ; return end

    local state, state_err = game.battle_session_get(session_id)
    if state_err ~= nil then output.error = state_err ; return end
    if state == nil then output.error = "battle session not found" ; return end

    local is_development = ctx.game ~= nil and ctx.game.status == "development"
    lib_battle_common.dlog("session_id=" .. session_id)

    -- Locate attacker and defender across all battle lines.
    local attacker_card, attacker_line_key, defender_card, defender_line_key, defender_side_void = resolve_cards(state)

    if attacker_card == nil then output.error = "attacker card not found in any battle line" ; return end
    if attacker_card.trigger == true then output.error = "attacker card has already attacked this turn" ; return end
    if defender_card == nil then output.error = "defender card not found in any battle line" ; return end

    local attacker_def, defender_def, def_err = resolve_item_defs(state, attacker_card, defender_card)
    if def_err ~= nil then output.error = def_err ; return end

    if is_development then
        log_card_info(attacker_card, defender_card, attacker_def, defender_def, defender_line_key, defender_side_void)
    end

    local damage_dealt = compute_damage(is_development, attacker_def)

    expose_cards(attacker_card, defender_card)

    local dmg_actions, dmg_err = lib_card_ability.deal_damage_to_character(
        state, attacker_card, defender_card, damage_dealt, state[defender_line_key], defender_side_void
    )
    if dmg_err ~= nil then output.error = dmg_err ; return end

    if is_development then
        local total_dmg     = defender_card.total_damage_received or 0
        local final_def_val = defender_card.final_def or 0
        local defeated_str  = total_dmg > final_def_val and "yes" or "no"
        lib_battle_common.dlog("defender.total_damage_received=" .. total_dmg .. " final_def=" .. final_def_val .. " defeated=" .. defeated_str)
    end

    attacker_card.trigger = true

    local atk_ability_actions, atk_ability_err = trigger_attacker_ability(
        state, attacker_card, attacker_def, defender_card, defender_def, defender_line_key, defender_side_void, damage_dealt
    )
    if atk_ability_err ~= nil then output.error = atk_ability_err ; return end

    local def_ability_actions, def_ability_err = trigger_defender_ability(
        state, attacker_card, attacker_def, defender_card, defender_def, damage_dealt
    )
    if def_ability_err ~= nil then output.error = def_ability_err ; return end

    append_client_actions(state, attacker_card, defender_card, defender_side_void, dmg_actions, atk_ability_actions, def_ability_actions)

    handle_ability_type_attacker(state, attacker_card, attacker_line_key, attacker_def)

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