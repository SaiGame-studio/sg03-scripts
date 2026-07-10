-- lib_card_ability
-- Card ability triggering system.
-- is_library = true
--
-- Abilities are read from `card.metadata.abilities` - a comma-separated string
-- set on the item definition and carried onto the card instance.
-- Example: card.metadata.abilities = "double_strike,thorns"
-- A card with a nil/empty metadata.abilities string has no active abilities.
--
-- To add a new ability:
--   1. Create a library script in `Scripts`, for example `ability_<ability_key>.lua`.
--   2. Add its config to `get_ability_config`.
--   3. Add a branch in `_get_ability_library` so the dispatcher can call `<library>.execute(...)`.

-- Valid target_positions:
--   own_frontline
--   own_backline
--   own_hand
--   own_void
--   own_source
--   enemy_frontline
--   enemy_backline
--   enemy_hand
--   enemy_void
--   enemy_source

-- Parses card.metadata.abilities into an array of trimmed, non-empty keys.
-- Falls back to item_def.metadata.abilities when the card instance does not carry abilities.
local function _get_ability_keys(source_card, item_defs)
    if source_card == nil then return {} end
    local raw = source_card.metadata ~= nil and source_card.metadata.abilities or nil
    if (raw == nil or raw == "") and item_defs ~= nil and source_card.item_definition_code_name ~= nil then
        for _, item_def in ipairs(item_defs) do
            if item_def.item_code == source_card.item_definition_code_name then
                raw = item_def.metadata ~= nil and item_def.metadata.abilities or nil
                break
            end
        end
    end
    if raw == nil or raw == "" then return {} end
    local keys = {}
    for ability_key in string.gmatch(raw, "[^,]+") do
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

function get_ability_keys(source_card, item_defs)
    return _get_ability_keys(source_card, item_defs)
end

function get_ability_config(ability_key)
    local configs = {
        twin_reaper = { event = "on_attack", target_positions = { "enemy_frontline" } },
        spinning_slash = { event = "on_attack", target_positions = { "enemy_frontline" } },
        cross_guard = { event = "on_attack", target_positions = { "own_frontline" } },
        totem_pulse = { event = "on_defend", target_positions = { "own_frontline" } },
        back_stab = { event = "on_attack", target_positions = { "enemy_frontline" } },
    }
    return configs[ability_key]
end

-- Returns "alpha" or "omega" by scanning state lines for the given card.
local function _find_card_side(state, card)
    local alpha_lines = { state.alpha_front_line, state.alpha_back_line }
    local omega_lines = { state.omega_front_line, state.omega_back_line }
    for _, line in ipairs(alpha_lines) do
        if line ~= nil then
            for _, slot_card in ipairs(line) do
                if slot_card.inventory_item_id == card.inventory_item_id then return "alpha" end
            end
        end
    end
    for _, line in ipairs(omega_lines) do
        if line ~= nil then
            for _, slot_card in ipairs(line) do
                if slot_card.inventory_item_id == card.inventory_item_id then return "omega" end
            end
        end
    end
    return "unknown"
end

-- Looks up an item definition from state.item_defs by item_code.
local function _find_item_def(item_defs, code)
    if item_defs == nil or code == nil then return nil end
    for _, item_def in ipairs(item_defs) do
        if item_def.item_code == code then
            return item_def
        end
    end
    return nil
end

local function _build_named_zones(state)
    return {
        { zone = state.alpha_front_line or {},  zone_key = "alpha_front_line" },
        { zone = state.alpha_back_line or {},   zone_key = "alpha_back_line" },
        { zone = state.alpha_hand or {},        zone_key = "alpha_hand" },
        { zone = state.alpha_the_void or {},    zone_key = "alpha_the_void" },
        { zone = state.alpha_the_source or {},  zone_key = "alpha_the_source" },
        { zone = state.omega_front_line or {},  zone_key = "omega_front_line" },
        { zone = state.omega_back_line or {},   zone_key = "omega_back_line" },
        { zone = state.omega_hand or {},        zone_key = "omega_hand" },
        { zone = state.omega_the_void or {},    zone_key = "omega_the_void" },
        { zone = state.omega_the_source or {},  zone_key = "omega_the_source" },
    }
end

local function _find_card_zone_key(state, target_card)
    if target_card == nil or target_card.inventory_item_id == nil or target_card.inventory_item_id == "" then
        return nil
    end
    for _, entry in ipairs(_build_named_zones(state)) do
        for _, zone_card in ipairs(entry.zone) do
            if zone_card.inventory_item_id == target_card.inventory_item_id then
                return entry.zone_key
            end
        end
    end
    return nil
end

local function _zone_position_key(source_side, zone_key)
    if source_side == nil or source_side == "" or source_side == "unknown" then return nil end
    if zone_key == nil or zone_key == "" then return nil end

    local zone_side
    if string.sub(zone_key, 1, 6) == "alpha_" then
        zone_side = "alpha"
    elseif string.sub(zone_key, 1, 6) == "omega_" then
        zone_side = "omega"
    else
        return nil
    end

    local relation = zone_side == source_side and "own_" or "enemy_"
    local zone_name = string.sub(zone_key, 7)
    if zone_name == "front_line" then return relation .. "frontline" end
    if zone_name == "back_line" then return relation .. "backline" end
    if zone_name == "hand" then return relation .. "hand" end
    if zone_name == "the_void" then return relation .. "void" end
    if zone_name == "the_source" then return relation .. "source" end
    return nil
end

function get_target_position_key(state, source_card, zone_key)
    local source_side = _find_card_side(state, source_card)
    return _zone_position_key(source_side, zone_key)
end

function can_ability_target_position(state, source_card, ability_key, zone_key)
    local ability_def = get_ability_config(ability_key)
    if ability_def == nil then
        return false, "unknown ability key: " .. tostring(ability_key)
    end

    local target_position = get_target_position_key(state, source_card, zone_key)
    if target_position == nil then
        return false, "unsupported target zone: " .. tostring(zone_key)
    end

    local target_positions = ability_def.target_positions or {}
    for _, allowed_position in ipairs(target_positions) do
        if allowed_position == target_position then
            return true, nil
        end
    end
    return false, target_position
end

local function _validate_defender_target_position(state, source_card, ability_key, event_data)
    local defender_card = event_data ~= nil and event_data.defender_card or nil
    if defender_card == nil then return nil end

    -- on_attack abilities can fire after the primary hit has already moved the
    -- defender to the void, so prefer the original targeted line when present.
    local defender_zone_key = event_data ~= nil and event_data.defender_line_key or nil
    if defender_zone_key == nil or defender_zone_key == "" then
        defender_zone_key = _find_card_zone_key(state, defender_card)
    end
    if defender_zone_key == nil then
        return "defender card not found in battle state for ability target validation"
    end

    local allowed, allowed_info = can_ability_target_position(state, source_card, ability_key, defender_zone_key)
    if allowed then
        event_data.defender_line_key = defender_zone_key
        if defender_zone_key == "alpha_the_void" or defender_zone_key == "omega_the_void" then
            event_data.defender_side_void = defender_zone_key
        end
        return nil
    end
    return "target position is not allowed for ability " .. tostring(ability_key) .. ": " .. tostring(allowed_info)
end

local function _find_line_card_by_code(line, code_name)
    for _, line_card in ipairs(line or {}) do
        if line_card.item_definition_code_name == code_name then
            return line_card
        end
    end
    return nil
end

-- Applies damage to target_card, clears its slot from target_line if defeated, and
-- returns the resulting client actions ("card_ability_defeated" or "card_ability_damaged").
-- target_line and void_key may be nil if line removal is not needed.
function deal_damage_to_character(state, attacker_card, target_card, damage, target_line, void_key)
    lib_battle_common.dlog("== [ability] deal_damage_to_character ====================")
    if not lib_battle_common.check_card_type(state.item_defs, attacker_card, "character") then
        lib_battle_common.dlog("[ability] deal_damage: skip - attacker is not character type")
        return {}, nil
    end
    if not lib_battle_common.check_card_type(state.item_defs, target_card, "character") then
        lib_battle_common.dlog("[ability] deal_damage: skip - target is not character type")
        return {}, nil
    end
    if lib_battle_common.is_card_stunned(attacker_card) then
        lib_battle_common.dlog("[ability] deal_damage: skip - attacker stunned (stun_count=" .. (attacker_card.stun_count or 0) .. ")")
        return {}, nil
    end

    local final_def = target_card.final_def or 0

    local prev_damage = target_card.total_damage_received or 0
    target_card.total_damage_received = prev_damage + damage
    local defeated = target_card.total_damage_received >= final_def
    lib_battle_common.dlog("[ability] deal_damage: final_def=" .. final_def .. " prev_damage=" .. prev_damage .. " new_total=" .. target_card.total_damage_received .. " defeated=" .. (defeated and "yes" or "no"))

    local target_side = void_key == "alpha_the_void" and "alpha" or "omega"
    local damage_actions = {}
    if defeated then
        if target_line ~= nil then
            lib_battle_common.remove_card_from_line(target_line, target_card.inventory_item_id)
        end
        if void_key ~= nil then
            if state[void_key] == nil then state[void_key] = {} end
            table.insert(state[void_key], target_card)
        end
        table.insert(damage_actions, target_side .. "_card_sent_to_void:" .. target_card.inventory_item_id)
    else
        table.insert(damage_actions, target_side .. "_card_damaged:" .. target_card.inventory_item_id .. "," .. target_card.total_damage_received)
    end
    return damage_actions, nil
end

local function _get_ability_library(ability_key)
    if ability_key == "twin_reaper" then
        return ability_twin_reaper
    elseif ability_key == "spinning_slash" then
        return ability_spinning_slash
    elseif ability_key == "cross_guard" then
        return ability_cross_guard
    elseif ability_key == "totem_pulse" then
        return ability_totem_pulse
    elseif ability_key == "back_stab" then
        return ability_back_stab
    end
    return nil
end

local function _get_item_def_race(item_def)
    if item_def == nil or item_def.metadata == nil then return nil end
    return item_def.metadata.race
end

local function _find_line_character_by_race(line, item_defs, race)
    for _, line_card in ipairs(line or {}) do
        local has_id = line_card.inventory_item_id ~= nil and line_card.inventory_item_id ~= ""
        if has_id then
            local item_def = _find_item_def(item_defs, line_card.item_definition_code_name)
            local card_type = item_def ~= nil and item_def.metadata ~= nil and item_def.metadata.type or nil
            local card_race = _get_item_def_race(item_def)
            if card_type == "character" and card_race == race then
                return line_card
            end
        end
    end
    return nil
end

local function _build_ability_helpers()
    return {
        lib_battle_common = lib_battle_common,
        deal_damage_to_character = deal_damage_to_character,
        find_card_side = _find_card_side,
        find_item_def = _find_item_def,
        find_line_card_by_code = _find_line_card_by_code,
        find_line_character_by_race = _find_line_character_by_race,
    }
end

-- Calls the handler for one ability key only if its registered event matches trigger_event.
-- Returns: extra_client_actions (table), err (string or nil)
local function _dispatch_one_ability(state, source_card, key, trigger_event, event_data)
    lib_battle_common.dlog("-- [ability] _dispatch_one_ability ----------------------")
    local ability_def = get_ability_config(key)
    if ability_def == nil then
        lib_battle_common.dlog("[ability] dispatch: key=" .. tostring(key) .. " UNKNOWN - not registered in get_ability_config")
        return {}, "unknown ability key: " .. tostring(key)
    end
    if ability_def.event ~= nil and ability_def.event ~= trigger_event then
        lib_battle_common.dlog("[ability] dispatch: key=" .. key .. " skip - registered for event=" .. ability_def.event .. " but current event=" .. trigger_event)
        return {}, nil
    end

    local target_err = _validate_defender_target_position(state, source_card, key, event_data)
    if target_err ~= nil then
        lib_battle_common.dlog("[ability] dispatch: key=" .. key .. " target validation failed - " .. target_err)
        return {}, target_err
    end

    local ability_library = _get_ability_library(key)
    if ability_library == nil or type(ability_library.execute) ~= "function" then
        lib_battle_common.dlog("[ability] dispatch: key=" .. key .. " ERROR - execute handler missing")
        return {}, "no handler for ability key: " .. tostring(key)
    end

    lib_battle_common.dlog("[ability] dispatch: key=" .. key .. " FIRING on event=" .. trigger_event)
    return ability_library.execute(state, source_card, event_data, _build_ability_helpers())
end

-- Fires ALL abilities listed in card.metadata.abilities for the given trigger_event.
-- Stops and returns the first error encountered.
-- Returns: extra_client_actions (table), err (string or nil)
function trigger_card_ability(state, source_card, trigger_event, event_data)
    lib_battle_common.dlog("-- [ability] trigger_card_ability ----------------------")
    local keys = _get_ability_keys(source_card, state.item_defs)
    if #keys == 0 then
        return {}, nil
    end

    local all_actions = {}

    -- Expose the source card when it activates abilities.
    source_card.face_up = true
    source_card.expose = true
    local source_side = _find_card_side(state, source_card)
    table.insert(all_actions, source_side .. "_card_expose:" .. source_card.inventory_item_id)

    for _, ability_key in ipairs(keys) do
        local ability_actions, err = _dispatch_one_ability(state, source_card, ability_key, trigger_event, event_data)
        if err ~= nil then return all_actions, err end
        for _, action in ipairs(ability_actions) do
            table.insert(all_actions, action)
        end
    end
    return all_actions, nil
end

-- Triggers a single ability by its key directly, bypassing metadata lookup.
-- Use when the card IS the ability (metadata.type == "ability") and its
-- item_definition_code_name is the ability key.
-- Returns: extra_client_actions (table), err (string or nil)
function trigger_ability_by_key(state, source_card, ability_key, trigger_event, event_data)
    lib_battle_common.dlog("-- [ability] trigger_ability_by_key: key=" .. tostring(ability_key) .. " event=" .. tostring(trigger_event) .. " ----------------------")
    local all_actions = {}
    source_card.face_up = true
    source_card.expose = true
    local source_side = _find_card_side(state, source_card)
    table.insert(all_actions, source_side .. "_card_expose:" .. source_card.inventory_item_id)
    local ability_actions, err = _dispatch_one_ability(state, source_card, ability_key, trigger_event, event_data)
    if err ~= nil then return all_actions, err end
    for _, action in ipairs(ability_actions) do
        table.insert(all_actions, action)
    end
    return all_actions, nil
end
