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
local _known_abilities = {
    twin_reaper    = { event = "on_attack", target_positions = { "enemy_frontline" } }, -- also strikes the card to the right of the target (fallback: left)
    spinning_slash = { event = "on_attack", target_positions = { "enemy_frontline" } }, -- requires azure_blade in front-line; deals attacker.metadata.atk_add + azure_blade.metadata.atk
    cross_guard    = { event = "on_attack", target_positions = { "own_frontline" } }, -- increases target's final_def by 200 (triggered directly as ability-type card)
    totem_pulse    = { event = "on_defend", target_positions = { "own_frontline" } }, -- adds base_stats.def_add to every card in its own side's front_line
}

-- ─── Internal helpers ─────────────────────────────────────────────────────────

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

function get_ability_keys(source_card, item_defs)
    return _get_ability_keys(source_card, item_defs)
end

function get_ability_config(ability_key)
    return _known_abilities[ability_key]
end

-- ─── Shared internal helpers ────────────────────────────────────────────────

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
        if item_def.item_code == code then return item_def end
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
    local ability_def = _known_abilities[ability_key]
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

local function _line_has_card_code(line, code_name)
    for _, line_card in ipairs(line or {}) do
        if line_card.item_definition_code_name == code_name then
            return true
        end
    end
    return false
end

local function _find_line_card_by_code(line, code_name)
    for _, line_card in ipairs(line or {}) do
        if line_card.item_definition_code_name == code_name then
            return line_card
        end
    end
    return nil
end

local function _find_line_card_by_code(line, code_name)
    for _, line_card in ipairs(line or {}) do
        if line_card.item_definition_code_name == code_name then
            return line_card
        end
    end
    return nil
end

-- ─── Built-in ability handlers ────────────────────────────────────────────────
-- Each handler is only called when the right trigger_event already matches.
-- No need to guard the event type inside the handler.

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

    local target_side   = void_key == "alpha_the_void" and "alpha" or "omega"
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

-- twin_reaper: after the primary attack, also strikes the card immediately to the right
-- of the target (by slot_index). Falls back to the left if no card to the right.
-- Damage equals the attacker's base_atk.
local function _handle_twin_reaper(state, attacker_card, event_data)
    lib_battle_common.dlog("== [ability] twin_reaper ====================")
    local defender     = (event_data or {}).defender_card
    if defender == nil then
        lib_battle_common.dlog("[ability] twin_reaper: skip - defender_card is nil in event_data")
        return {}, nil
    end

    local line_key      = (event_data or {}).defender_line_key
    local void_key      = (event_data or {}).defender_side_void
    local defender_line = line_key ~= nil and state[line_key] or nil
    if defender_line == nil then
        lib_battle_common.dlog("[ability] twin_reaper: skip - defender_line_key missing or line is nil (line_key=" .. tostring(line_key) .. ")")
        return {}, nil
    end

    local defender_slot = defender.slot_index or 0
    lib_battle_common.dlog("[ability] twin_reaper: defender=" .. defender.inventory_item_id .. " slot=" .. defender_slot)

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
    if target == nil then
        lib_battle_common.dlog("[ability] twin_reaper: no adjacent card found, skip")
        return {}, nil
    end

    local attacker_def  = (event_data or {}).attacker_def
    local damage        = (attacker_def ~= nil and attacker_def.base_stats and attacker_def.base_stats.atk) or 1
    lib_battle_common.dlog("[ability] twin_reaper: target=" .. target.inventory_item_id .. " slot=" .. (target.slot_index or 0) .. " damage=" .. damage)

    local attacker_side   = _find_card_side(state, attacker_card)
    local ability_actions = { attacker_side .. "_card_ability:" .. attacker_card.inventory_item_id .. ",twin_reaper," .. target.inventory_item_id }
    local damage_actions, dmg_err = deal_damage_to_character(state, attacker_card, target, damage, defender_line, void_key)
    if dmg_err ~= nil then return ability_actions, dmg_err end
    for _, action in ipairs(damage_actions) do
        table.insert(ability_actions, action)
    end
    return ability_actions, nil
end

-- spinning_slash: requires at least one azure_blade card in the attacker's front-line.
-- Damage = attacker.metadata.atk_add + azure_blade.metadata.atk (first azure_blade found).
local function _handle_spinning_slash(state, attacker_card, event_data)
    lib_battle_common.dlog("== [ability] spinning_slash ====================")
    local defender  = (event_data or {}).defender_card
    if defender == nil then
        lib_battle_common.dlog("[ability] spinning_slash: skip - defender_card is nil in event_data")
        return {}, nil
    end

    local line_key  = (event_data or {}).defender_line_key
    local void_key  = (event_data or {}).defender_side_void

    local attacker_side = _find_card_side(state, attacker_card)
    local front_line_key = attacker_side .. "_front_line"
    local front_line = state[front_line_key] or {}
    lib_battle_common.dlog("[ability] spinning_slash: attacker=" .. attacker_card.inventory_item_id .. " side=" .. attacker_side .. " selecting from " .. front_line_key)

    local azure_blade_card = _find_line_card_by_code(front_line, "azure_blade")
    if azure_blade_card == nil then
        lib_battle_common.dlog("[ability] spinning_slash: error - no azure_blade in " .. front_line_key)
        return {}, "spinning_slash requires azure_blade in front_line"
    end
    if defender.inventory_item_id == azure_blade_card.inventory_item_id then
        lib_battle_common.dlog("[ability] spinning_slash: error - defender matches selected azure_blade id=" .. tostring(azure_blade_card.inventory_item_id))
        return {}, "spinning_slash cannot target the selected azure_blade"
    end

    local attacker_item_def   = _find_item_def(state.item_defs, attacker_card.item_definition_code_name)
    local azure_blade_item_def = _find_item_def(state.item_defs, azure_blade_card.item_definition_code_name)
    local atk_add  = (attacker_item_def ~= nil and attacker_item_def.base_stats ~= nil and attacker_item_def.base_stats.atk_add) or 0
    local blade_atk = (azure_blade_item_def ~= nil and azure_blade_item_def.metadata ~= nil and azure_blade_item_def.metadata.atk) or 0
    local damage   = atk_add + blade_atk
    lib_battle_common.dlog("[ability] spinning_slash: azure_blade=" .. azure_blade_card.inventory_item_id .. " atk_add=" .. atk_add .. " blade_atk=" .. blade_atk .. " total_damage=" .. damage)

    local defender_line = line_key ~= nil and state[line_key] or nil
    azure_blade_card.face_up = true
    azure_blade_card.expose  = true
    local ability_actions = {
        attacker_side .. "_card_expose:" .. azure_blade_card.inventory_item_id,
        attacker_side .. "_card_ability:" .. attacker_card.inventory_item_id .. ",spinning_slash," .. defender.inventory_item_id
    }
    local damage_actions, dmg_err = deal_damage_to_character(state, azure_blade_card, defender, damage, defender_line, void_key)
    if dmg_err ~= nil then return ability_actions, dmg_err end
    for _, action in ipairs(damage_actions) do
        table.insert(ability_actions, action)
    end
    return ability_actions, nil
end

-- cross_guard: when played as attacker (ability-type), increases the target card's final_def by 200.
-- Requires an azure_blade card in the attacker's front line; target may be in any zone.
local function _handle_cross_guard(state, source_card, event_data)
    lib_battle_common.dlog("== [ability] cross_guard ====================")
    local target_card = (event_data or {}).defender_card
    if target_card == nil then
        lib_battle_common.dlog("[ability] cross_guard: skip - defender_card is nil in event_data")
        return {}, nil
    end

    local source_side = _find_card_side(state, source_card)
    local source_front_line_key = source_side .. "_front_line"
    local azure_blade_card = _find_line_card_by_code(state[source_front_line_key], "azure_blade")
    if azure_blade_card == nil then
        lib_battle_common.dlog("[ability] cross_guard: error - no azure_blade in " .. source_front_line_key)
        return {}, "cross_guard requires azure_blade in front_line"
    end

    local guard_bonus = 200
    local prev_def = target_card.final_def or 0
    target_card.final_def = prev_def + guard_bonus
    azure_blade_card.face_up = true
    azure_blade_card.expose  = true
    lib_battle_common.dlog("[ability] cross_guard: target=" .. target_card.inventory_item_id .. " final_def " .. prev_def .. " -> " .. target_card.final_def)
    local guard_actions = {
        source_side .. "_card_expose:" .. azure_blade_card.inventory_item_id,
        source_side .. "_card_ability:" .. source_card.inventory_item_id .. ",cross_guard," .. target_card.inventory_item_id
    }
    return guard_actions, nil
end

-- totem_pulse: on_defend, adds base_stats.def_add from the totem's item def to
-- every real card in its own side's front_line.
-- Only activates when at least one goblin_shaman in the front_line has not yet triggered.
local function _find_untriggered_goblin_shaman(front_line)
    for _, front_card in ipairs(front_line) do
        local has_id   = front_card.inventory_item_id ~= nil and front_card.inventory_item_id ~= ""
        local is_shaman = front_card.item_definition_code_name == "goblin_shaman"
        if has_id and is_shaman and front_card.trigger ~= true then
            return front_card
        end
    end
    return nil
end

local function _handle_totem_pulse(state, source_card, event_data)
    lib_battle_common.dlog("== [ability] totem_pulse ====================")
    local source_side    = _find_card_side(state, source_card)
    local front_line_key = source_side .. "_front_line"
    local front_line     = state[front_line_key] or {}
    local totem_item_def = _find_item_def(state.item_defs, source_card.item_definition_code_name)
    local def_add        = (totem_item_def ~= nil and totem_item_def.base_stats ~= nil and totem_item_def.base_stats.def_add) or 0
    lib_battle_common.dlog("[ability] totem_pulse: source=" .. source_card.inventory_item_id .. " side=" .. source_side .. " def_add=" .. def_add)
    local shaman_card = _find_untriggered_goblin_shaman(front_line)
    if shaman_card == nil then
        lib_battle_common.dlog("[ability] totem_pulse: ed goblin_shaman in " .. front_line_key .. ", skip")
        return {}, nil
    end
    lib_battle_common.dlog("[ability] totem_pulse: untriggered goblin_shaman found: " .. shaman_card.inventory_item_id)
    local ability_actions = {}
    for _, front_card in ipairs(front_line) do
        local has_id = front_card.inventory_item_id ~= nil and front_card.inventory_item_id ~= ""
        if has_id then
            local prev_def = front_card.final_def or 0
            front_card.final_def = prev_def + def_add
            lib_battle_common.dlog("[ability] totem_pulse: buffed card=" .. front_card.inventory_item_id .. " final_def " .. prev_def .. " -> " .. front_card.final_def)
            local buff_action = source_side .. "_card_ability:" .. source_card.inventory_item_id .. ",totem_pulse," .. front_card.inventory_item_id
            table.insert(ability_actions, buff_action)
        end
    end
    -- Send the totem card itself to the void after use.
    local back_line_key  = source_side .. "_back_line"
    local back_line      = state[back_line_key] or {}
    lib_battle_common.remove_card_from_line(back_line, source_card.inventory_item_id)
    local void_key = source_side .. "_the_void"
    if state[void_key] == nil then state[void_key] = {} end
    table.insert(state[void_key], source_card)
    lib_battle_common.dlog("[ability] totem_pulse: source card sent to void=" .. void_key .. " id=" .. source_card.inventory_item_id)
    table.insert(ability_actions, source_side .. "_card_sent_to_void:" .. source_card.inventory_item_id)
    return ability_actions, nil
end

-- ─── Ability Dispatcher ───────────────────────────────────────────────────────

-- Calls the handler for one ability key only if its registered event matches trigger_event.
-- Returns: extra_client_actions (table), err (string or nil)
local function _dispatch_one_ability(state, source_card, key, trigger_event, event_data)
    lib_battle_common.dlog("-- [ability] _dispatch_one_ability ----------------------")
    local ability_def = _known_abilities[key]
    if ability_def == nil then
        lib_battle_common.dlog("[ability] dispatch: key=" .. tostring(key) .. " UNKNOWN - not registered in _known_abilities")
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

    lib_battle_common.dlog("[ability] dispatch: key=" .. key .. " FIRING on event=" .. trigger_event)
    if key == "twin_reaper" then
        return _handle_twin_reaper(state, source_card, event_data)
    elseif key == "spinning_slash" then
        return _handle_spinning_slash(state, source_card, event_data)
    elseif key == "cross_guard" then
        return _handle_cross_guard(state, source_card, event_data)
    elseif key == "totem_pulse" then
        return _handle_totem_pulse(state, source_card, event_data)
    else
        lib_battle_common.dlog("[ability] dispatch: key=" .. key .. " ERROR - no handler defined")
        return {}, "no handler for ability key: " .. tostring(key)
    end
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
    source_card.expose  = true
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
    source_card.expose  = true
    local source_side = _find_card_side(state, source_card)
    table.insert(all_actions, source_side .. "_card_expose:" .. source_card.inventory_item_id)
    local ability_actions, err = _dispatch_one_ability(state, source_card, ability_key, trigger_event, event_data)
    if err ~= nil then return all_actions, err end
    for _, action in ipairs(ability_actions) do
        table.insert(all_actions, action)
    end
    return all_actions, nil
end
