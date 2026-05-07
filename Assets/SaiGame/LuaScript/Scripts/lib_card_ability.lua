-- lib_card_ability
-- Card ability triggering system.
-- is_library = true
--
-- Abilities are read from `card.metadata.abilities` — a comma-separated string
-- set on the item definition and carried onto the card instance.
-- Example: card.metadata.abilities = "double_strike,thorns"
-- A card with a nil/empty metadata.abilities string has no active abilities.
--
-- To add a new ability:
--   1. Add its key to _known_abilities below.
--   2. Write a handler: local function _handle_<key>(state, card, trigger_event, context)
--        event_data for "on_attack":  { defender_card, damage_dealt, defender_defeated, attacker_def, defender_def, defender_line_key, defender_side_void }
--        event_data for "on_damaged": { attacker_card, damage_received, attacker_def, defender_def }
--        Returns: extra_client_actions (table), err (string or nil)
--   3. Add an elseif branch in _dispatch_one_ability's dispatch block.

local _known_abilities = {
    twin_reaper = { event = "on_attack" },   -- also strikes the card to the right of the target (fallback: left)
}

-- ─── Internal helpers ─────────────────────────────────────────────────────────

-- Parses card.metadata.abilities into an array of trimmed, non-empty keys.
local function _get_ability_keys(source_card)
    if source_card == nil then return {} end
    local raw = source_card.metadata ~= nil and source_card.metadata.abilities or nil
    if raw == nil or raw == "" then return {} end
    local keys = {}
    for ability_key in string.gmatch(raw, "[^,]+") do
        -- trim whitespace
        ability_key = string.match(ability_key, "^%s*(.-)%s*$")
        if ability_key ~= "" then
            table.insert(keys, ability_key)
        end
    end
    return keys
end

-- Returns true when the card has at least one ability in metadata.
function is_ability_registered(source_card)
    return #_get_ability_keys(source_card) > 0
end

-- ─── Shared internal helpers ────────────────────────────────────────────────

-- Looks up an item definition from state.item_defs by item_code.
local function _find_item_def(item_defs, code)
    if item_defs == nil or code == nil then return nil end
    for _, item_def in ipairs(item_defs) do
        if item_def.item_code == code then return item_def end
    end
    return nil
end

-- ─── Built-in ability handlers ────────────────────────────────────────────────
-- Each handler is only called when the right trigger_event already matches.
-- No need to guard the event type inside the handler.

-- Applies damage to target_card, removes it from target_line if defeated, and
-- returns the resulting client actions ("card_ability_defeated" or "card_ability_damaged").
-- target_line and void_key may be nil if line removal is not needed.
function deal_damage_to_character(state, target_card, damage, target_line, void_key)
    -- Always resolve final_def from item def (same as do_normal_attack in alpha_attacking).
    -- Buffs will be applied here later.
    local target_item_def = _find_item_def(state.item_defs, target_card.item_definition_code_name)
    local base_def        = (target_item_def ~= nil and target_item_def.base_stats and target_item_def.base_stats.def) or 0
    local final_def       = base_def
    target_card.final_def = final_def   -- always persist, matches alpha_attacking pattern

    local prev_damage = target_card.total_damage_received or 0
    target_card.total_damage_received = prev_damage + damage
    local defeated = target_card.total_damage_received > final_def

    local damage_actions = {}
    if defeated then
        if target_line ~= nil then
            for i, slot_card in ipairs(target_line) do
                if slot_card.inventory_item_id == target_card.inventory_item_id then
                    table.remove(target_line, i)
                    break
                end
            end
        end
        if void_key ~= nil then
            if state[void_key] == nil then state[void_key] = {} end
            table.insert(state[void_key], target_card)
        end
        table.insert(damage_actions, "card_ability_defeated:" .. target_card.inventory_item_id)
    else
        table.insert(damage_actions, "card_ability_damaged:" .. target_card.inventory_item_id .. "," .. target_card.total_damage_received)
    end
    return damage_actions, nil
end

-- twin_reaper: after the primary attack, also strikes the card immediately to the right
-- of the target (by slot_index). Falls back to the left if no card to the right.
-- Damage equals the attacker's base_atk.
local function _handle_twin_reaper(state, attacker_card, event_data)
    local defender     = (event_data or {}).defender_card
    if defender == nil then return {}, nil end

    local line_key      = (event_data or {}).defender_line_key
    local void_key      = (event_data or {}).defender_side_void
    local defender_line = line_key ~= nil and state[line_key] or nil
    if defender_line == nil then return {}, nil end

    local defender_slot = defender.slot_index or 0

    -- Prefer right neighbour (slot_index + 1), fallback to left (slot_index - 1).
    local target
    for _, slot_card in ipairs(defender_line) do
        if slot_card.inventory_item_id ~= nil and slot_card.inventory_item_id ~= ""
           and slot_card.inventory_item_id ~= defender.inventory_item_id
           and (slot_card.slot_index or 0) == defender_slot + 1 then
            target = slot_card
            break
        end
    end
    if target == nil then
        for _, slot_card in ipairs(defender_line) do
            if slot_card.inventory_item_id ~= nil and slot_card.inventory_item_id ~= ""
               and slot_card.inventory_item_id ~= defender.inventory_item_id
               and (slot_card.slot_index or 0) == defender_slot - 1 then
                target = slot_card
                break
            end
        end
    end
    if target == nil then return {}, nil end  -- no adjacent card found

    local attacker_def  = (event_data or {}).attacker_def
    local damage        = (attacker_def ~= nil and attacker_def.base_stats and attacker_def.base_stats.atk) or 1

    local ability_actions = { "card_ability:" .. attacker_card.inventory_item_id .. ",twin_reaper," .. target.inventory_item_id }
    local damage_actions, dmg_err = deal_damage_to_character(state, target, damage, defender_line, void_key)
    if dmg_err ~= nil then return ability_actions, dmg_err end
    for _, action in ipairs(damage_actions) do
        table.insert(ability_actions, action)
    end
    return ability_actions, nil
end

-- ─── Ability Dispatcher ───────────────────────────────────────────────────────

-- Calls the handler for one ability key only if its registered event matches trigger_event.
-- Returns: extra_client_actions (table), err (string or nil)
local function _dispatch_one_ability(state, source_card, key, trigger_event, event_data)
    local ability_def = _known_abilities[key]
    if ability_def == nil then
        return {}, "unknown ability key: " .. tostring(key)
    end
    if ability_def.event ~= trigger_event then
        return {}, nil   -- this ability does not fire on this event
    end

    if key == "twin_reaper" then
        return _handle_twin_reaper(state, source_card, event_data)
    else
        return {}, "no handler for ability key: " .. tostring(key)
    end
end

-- Fires ALL abilities listed in card.metadata.abilities for the given trigger_event.
-- Stops and returns the first error encountered.
-- Returns: extra_client_actions (table), err (string or nil)
function trigger_card_ability(state, source_card, trigger_event, event_data)
    local keys = _get_ability_keys(source_card)
    if #keys == 0 then
        return {}, nil
    end

    local all_actions = {}
    for _, ability_key in ipairs(keys) do
        local ability_actions, err = _dispatch_one_ability(state, source_card, ability_key, trigger_event, event_data)
        if err ~= nil then return all_actions, err end
        for _, action in ipairs(ability_actions) do
            table.insert(all_actions, action)
        end
    end
    return all_actions, nil
end
