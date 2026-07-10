-- ability_all
-- Generated bundle from `Assets/SaiGame/LuaScript/AbilitySources`.
-- is_library = true

-- ability: twin_reaper
function twin_reaper_execute(state, attacker_card, event_data, helpers)
    local battle = helpers.lib_battle_common
    battle.dlog("== [ability] twin_reaper ====================")

    local defender = (event_data or {}).defender_card
    if defender == nil then
        battle.dlog("[ability] twin_reaper: skip - defender_card is nil in event_data")
        return {}, nil
    end

    local line_key = (event_data or {}).defender_line_key
    local void_key = (event_data or {}).defender_side_void
    local defender_line = line_key ~= nil and state[line_key] or nil
    if defender_line == nil then
        battle.dlog("[ability] twin_reaper: skip - defender_line_key missing or line is nil (line_key=" .. tostring(line_key) .. ")")
        return {}, nil
    end

    local defender_slot = defender.slot_index or 0
    battle.dlog("[ability] twin_reaper: defender=" .. defender.inventory_item_id .. " slot=" .. defender_slot)

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
        battle.dlog("[ability] twin_reaper: no adjacent card found, skip")
        return {}, nil
    end

    local attacker_def = (event_data or {}).attacker_def
    local damage = (attacker_def ~= nil and attacker_def.base_stats and attacker_def.base_stats.atk) or 1
    battle.dlog("[ability] twin_reaper: target=" .. target.inventory_item_id .. " slot=" .. (target.slot_index or 0) .. " damage=" .. damage)

    local attacker_side = helpers.find_card_side(state, attacker_card)
    local ability_actions = { attacker_side .. "_card_ability:" .. attacker_card.inventory_item_id .. ",twin_reaper," .. target.inventory_item_id }
    local damage_actions, dmg_err = helpers.deal_damage_to_character(state, attacker_card, target, damage, defender_line, void_key)
    if dmg_err ~= nil then return ability_actions, dmg_err end
    for _, action in ipairs(damage_actions) do
        table.insert(ability_actions, action)
    end
    return ability_actions, nil
end

-- ability: spinning_slash
function spinning_slash_execute(state, attacker_card, event_data, helpers)
    local battle = helpers.lib_battle_common
    battle.dlog("== [ability] spinning_slash ====================")

    local defender = (event_data or {}).defender_card
    if defender == nil then
        battle.dlog("[ability] spinning_slash: skip - defender_card is nil in event_data")
        return {}, nil
    end

    local line_key = (event_data or {}).defender_line_key
    local void_key = (event_data or {}).defender_side_void

    local attacker_side = helpers.find_card_side(state, attacker_card)
    local front_line_key = attacker_side .. "_front_line"
    local front_line = state[front_line_key] or {}
    battle.dlog("[ability] spinning_slash: attacker=" .. attacker_card.inventory_item_id .. " side=" .. attacker_side .. " selecting from " .. front_line_key)

    local azure_blade_card = helpers.find_line_card_by_code(front_line, "azure_blade")
    if azure_blade_card == nil then
        battle.dlog("[ability] spinning_slash: error - no azure_blade in " .. front_line_key)
        return {}, "spinning_slash requires azure_blade in front_line"
    end
    if defender.inventory_item_id == azure_blade_card.inventory_item_id then
        battle.dlog("[ability] spinning_slash: error - defender matches selected azure_blade id=" .. tostring(azure_blade_card.inventory_item_id))
        return {}, "spinning_slash cannot target the selected azure_blade"
    end

    local attacker_item_def = helpers.find_item_def(state.item_defs, attacker_card.item_definition_code_name)
    local azure_blade_item_def = helpers.find_item_def(state.item_defs, azure_blade_card.item_definition_code_name)
    local atk_add = (attacker_item_def ~= nil and attacker_item_def.base_stats ~= nil and attacker_item_def.base_stats.atk_add) or 0
    local blade_atk = (azure_blade_item_def ~= nil and azure_blade_item_def.metadata ~= nil and azure_blade_item_def.metadata.atk) or 0
    local damage = atk_add + blade_atk
    battle.dlog("[ability] spinning_slash: azure_blade=" .. azure_blade_card.inventory_item_id .. " atk_add=" .. atk_add .. " blade_atk=" .. blade_atk .. " total_damage=" .. damage)

    local defender_line = line_key ~= nil and state[line_key] or nil
    azure_blade_card.face_up = true
    azure_blade_card.expose = true
    local ability_actions = {
        attacker_side .. "_card_expose:" .. azure_blade_card.inventory_item_id,
        attacker_side .. "_card_ability:" .. attacker_card.inventory_item_id .. ",spinning_slash," .. defender.inventory_item_id
    }
    local damage_actions, dmg_err = helpers.deal_damage_to_character(state, azure_blade_card, defender, damage, defender_line, void_key)
    if dmg_err ~= nil then return ability_actions, dmg_err end
    for _, action in ipairs(damage_actions) do
        table.insert(ability_actions, action)
    end
    return ability_actions, nil
end

-- ability: cross_guard
function cross_guard_execute(state, source_card, event_data, helpers)
    local battle = helpers.lib_battle_common
    battle.dlog("== [ability] cross_guard ====================")

    local target_card = (event_data or {}).defender_card
    if target_card == nil then
        battle.dlog("[ability] cross_guard: skip - defender_card is nil in event_data")
        return {}, nil
    end

    local source_side = helpers.find_card_side(state, source_card)
    local source_front_line_key = source_side .. "_front_line"
    local azure_blade_card = helpers.find_line_card_by_code(state[source_front_line_key], "azure_blade")
    if azure_blade_card == nil then
        battle.dlog("[ability] cross_guard: error - no azure_blade in " .. source_front_line_key)
        return {}, "cross_guard requires azure_blade in front_line"
    end

    local guard_bonus = 200
    local prev_def = target_card.final_def or 0
    target_card.final_def = prev_def + guard_bonus
    azure_blade_card.face_up = true
    azure_blade_card.expose = true
    battle.dlog("[ability] cross_guard: target=" .. target_card.inventory_item_id .. " final_def " .. prev_def .. " -> " .. target_card.final_def)
    local guard_actions = {
        source_side .. "_card_expose:" .. azure_blade_card.inventory_item_id,
        source_side .. "_card_ability:" .. source_card.inventory_item_id .. ",cross_guard," .. target_card.inventory_item_id
    }
    return guard_actions, nil
end

-- ability: totem_pulse
function totem_pulse_find_untriggered_goblin_shaman(front_line)
    for _, front_card in ipairs(front_line) do
        local has_id = front_card.inventory_item_id ~= nil and front_card.inventory_item_id ~= ""
        local is_shaman = front_card.item_definition_code_name == "goblin_shaman"
        if has_id and is_shaman and front_card.trigger ~= true then
            return front_card
        end
    end
    return nil
end

function totem_pulse_execute(state, source_card, event_data, helpers)
    local battle = helpers.lib_battle_common
    battle.dlog("== [ability] totem_pulse ====================")

    local source_side = helpers.find_card_side(state, source_card)
    local front_line_key = source_side .. "_front_line"
    local front_line = state[front_line_key] or {}
    local totem_item_def = helpers.find_item_def(state.item_defs, source_card.item_definition_code_name)
    local def_add = (totem_item_def ~= nil and totem_item_def.base_stats ~= nil and totem_item_def.base_stats.def_add) or 0
    battle.dlog("[ability] totem_pulse: source=" .. source_card.inventory_item_id .. " side=" .. source_side .. " def_add=" .. def_add)

    local shaman_card = totem_pulse_find_untriggered_goblin_shaman(front_line)
    if shaman_card == nil then
        battle.dlog("[ability] totem_pulse: no untriggered goblin_shaman in " .. front_line_key .. ", skip")
        return {}, nil
    end

    battle.dlog("[ability] totem_pulse: untriggered goblin_shaman found: " .. shaman_card.inventory_item_id)
    local ability_actions = {}
    for _, front_card in ipairs(front_line) do
        local has_id = front_card.inventory_item_id ~= nil and front_card.inventory_item_id ~= ""
        if has_id then
            local prev_def = front_card.final_def or 0
            front_card.final_def = prev_def + def_add
            battle.dlog("[ability] totem_pulse: buffed card=" .. front_card.inventory_item_id .. " final_def " .. prev_def .. " -> " .. front_card.final_def)
            local buff_action = source_side .. "_card_ability:" .. source_card.inventory_item_id .. ",totem_pulse," .. front_card.inventory_item_id
            table.insert(ability_actions, buff_action)
        end
    end

    local back_line_key = source_side .. "_back_line"
    local back_line = state[back_line_key] or {}
    battle.remove_card_from_line(back_line, source_card.inventory_item_id)
    local void_key = source_side .. "_the_void"
    if state[void_key] == nil then state[void_key] = {} end
    table.insert(state[void_key], source_card)
    battle.dlog("[ability] totem_pulse: source card sent to void=" .. void_key .. " id=" .. source_card.inventory_item_id)
    table.insert(ability_actions, source_side .. "_card_sent_to_void:" .. source_card.inventory_item_id)
    return ability_actions, nil
end

-- ability: back_stab
function back_stab_execute(state, source_card, event_data, helpers)
    local battle = helpers.lib_battle_common
    battle.dlog("== [ability] back_stab ====================")

    local defender = (event_data or {}).defender_card
    if defender == nil then
        battle.dlog("[ability] back_stab: skip - defender_card is nil in event_data")
        return {}, nil
    end

    local source_side = helpers.find_card_side(state, source_card)
    local front_line_key = source_side .. "_front_line"
    local front_line = state[front_line_key] or {}
    local goblin_card = helpers.find_line_character_by_race(front_line, state.item_defs, "goblin")
    if goblin_card == nil then
        battle.dlog("[ability] back_stab: error - no goblin character in " .. front_line_key)
        return {}, "back_stab requires a goblin character in front_line"
    end

    if defender.inventory_item_id == goblin_card.inventory_item_id then
        battle.dlog("[ability] back_stab: error - defender matches selected goblin id=" .. tostring(goblin_card.inventory_item_id))
        return {}, "back_stab cannot target the selected goblin"
    end

    local line_key = (event_data or {}).defender_line_key
    local void_key = (event_data or {}).defender_side_void
    local defender_line = line_key ~= nil and state[line_key] or nil

    local goblin_item_def = helpers.find_item_def(state.item_defs, goblin_card.item_definition_code_name)
    local damage = (goblin_item_def ~= nil and goblin_item_def.base_stats ~= nil and goblin_item_def.base_stats.atk) or 1
    battle.dlog("[ability] back_stab: goblin=" .. goblin_card.inventory_item_id .. " target=" .. defender.inventory_item_id .. " damage=" .. damage)

    goblin_card.face_up = true
    goblin_card.expose = true
    local ability_actions = {
        source_side .. "_card_expose:" .. goblin_card.inventory_item_id,
        source_side .. "_card_ability:" .. source_card.inventory_item_id .. ",back_stab," .. defender.inventory_item_id
    }
    local damage_actions, dmg_err = helpers.deal_damage_to_character(state, goblin_card, defender, damage, defender_line, void_key)
    if dmg_err ~= nil then return ability_actions, dmg_err end
    for _, action in ipairs(damage_actions) do
        table.insert(ability_actions, action)
    end
    return ability_actions, nil
end

