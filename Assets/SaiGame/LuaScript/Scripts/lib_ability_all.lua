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
function get_ability_config(ability_key)
    local configs = {
        twin_reaper = { target_positions = { "enemy_frontline" } },
        spinning_slash = { target_positions = { "enemy_frontline" }, is_character_ability = true },
        cross_guard = { target_positions = { "own_frontline" } },
        totem_pulse = { target_positions = { "own_frontline" } },
        back_stab = { target_positions = { "enemy_frontline" } },
        holy_glow = { target_positions = { "own_frontline", "own_backline", "own_source", "own_void" } },
    }
    return configs[ability_key]
end


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
    local ability_actions = { attacker_side .. "_card_ability:source=" .. attacker_card.inventory_item_id .. ",ability=twin_reaper,target=" .. target.inventory_item_id }
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

    local azure_blade_card = helpers.find_untriggered_card(front_line, function(c) return c.item_definition_code_name == "azure_blade" end)
    if azure_blade_card == nil then
        battle.dlog("[ability] spinning_slash: error - no untriggered azure_blade in " .. front_line_key)
        return {}, "spinning_slash requires untriggered azure_blade in front_line"
    end
    azure_blade_card.trigger = true

    local ability_item_def = helpers.find_item_def(state.item_defs, "spinning_slash")
    local atk_add = 0
    if ability_item_def ~= nil then
        if ability_item_def.base_stats ~= nil and ability_item_def.base_stats.atk_add then
            atk_add = ability_item_def.base_stats.atk_add
        elseif ability_item_def.metadata ~= nil and ability_item_def.metadata.atk_add then
            atk_add = ability_item_def.metadata.atk_add
        end
    end

    local azure_blade_item_def = helpers.find_item_def(state.item_defs, azure_blade_card.item_definition_code_name)
    local char_atk = (azure_blade_item_def ~= nil and azure_blade_item_def.base_stats ~= nil and azure_blade_item_def.base_stats.atk) or 0

    local damage = atk_add + char_atk
    battle.dlog("[ability] spinning_slash: azure_blade=" .. azure_blade_card.inventory_item_id .. " total_damage=" .. damage)

    local defender_line = line_key ~= nil and state[line_key] or nil
    local expose_action = helpers.expose_ability_selected_card(state, azure_blade_card)
    local ability_actions = {
        expose_action,
        attacker_side .. "_card_ability:source=" .. attacker_card.inventory_item_id .. ",ability=spinning_slash,target=" .. defender.inventory_item_id .. ",selected=" .. azure_blade_card.inventory_item_id
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
    local azure_blade_card = helpers.find_untriggered_card(state[source_front_line_key], function(c) return c.item_definition_code_name == "azure_blade" end)
    if azure_blade_card == nil then
        battle.dlog("[ability] cross_guard: error - no untriggered azure_blade in " .. source_front_line_key)
        return {}, "cross_guard requires untriggered azure_blade in front_line"
    end
    azure_blade_card.trigger = true

    local guard_bonus = 200
    local prev_def = target_card.final_def or 0
    target_card.final_def = prev_def + guard_bonus
    local expose_action = helpers.expose_ability_selected_card(state, azure_blade_card)
    battle.dlog("[ability] cross_guard: target=" .. target_card.inventory_item_id .. " final_def " .. prev_def .. " -> " .. target_card.final_def)
    local guard_actions = {
        expose_action,
        source_side .. "_card_ability:source=" .. source_card.inventory_item_id .. ",ability=cross_guard,target=" .. target_card.inventory_item_id .. ",selected=" .. azure_blade_card.inventory_item_id,
        source_side .. "_card_guarded:" .. target_card.inventory_item_id
    }
    return guard_actions, nil
end
-- ability: totem_pulse

function totem_pulse_execute(state, source_card, event_data, helpers)
    local battle = helpers.lib_battle_common
    battle.dlog("== [ability] totem_pulse ====================")

    local source_side = helpers.find_card_side(state, source_card)
    local front_line_key = source_side .. "_front_line"
    local front_line = state[front_line_key] or {}
    local totem_item_def = helpers.find_item_def(state.item_defs, source_card.item_definition_code_name)
    local def_add = (totem_item_def ~= nil and totem_item_def.base_stats ~= nil and totem_item_def.base_stats.def_add) or 0
    battle.dlog("[ability] totem_pulse: source=" .. source_card.inventory_item_id .. " side=" .. source_side .. " def_add=" .. def_add)

    local shaman_card = helpers.find_untriggered_card(front_line, function(c) return c.item_definition_code_name == "goblin_shaman" end)
    if shaman_card == nil then
        battle.dlog("[ability] totem_pulse: error - no untriggered goblin_shaman in " .. front_line_key)
        return {}, "totem_pulse requires untriggered goblin_shaman in front_line"
    end

    battle.dlog("[ability] totem_pulse: untriggered goblin_shaman found: " .. shaman_card.inventory_item_id)
    shaman_card.trigger = true
    local ability_actions = {}
    local expose_action = helpers.expose_ability_selected_card(state, shaman_card)
    if expose_action ~= nil then table.insert(ability_actions, expose_action) end
    for _, front_card in ipairs(front_line) do
        local has_id = front_card.inventory_item_id ~= nil and front_card.inventory_item_id ~= ""
        if has_id then
            local prev_def = front_card.final_def or 0
            front_card.final_def = prev_def + def_add
            battle.dlog("[ability] totem_pulse: buffed card=" .. front_card.inventory_item_id .. " final_def " .. prev_def .. " -> " .. front_card.final_def)
            local buff_action = source_side .. "_card_ability:source=" .. source_card.inventory_item_id .. ",ability=totem_pulse,target=" .. front_card.inventory_item_id .. ",selected=" .. shaman_card.inventory_item_id
            table.insert(ability_actions, buff_action)
            table.insert(ability_actions, source_side .. "_card_guarded:" .. front_card.inventory_item_id)
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
    local goblin_card = helpers.find_untriggered_card(front_line, function(c)
        local def = helpers.find_item_def(state.item_defs, c.item_definition_code_name)
        return def ~= nil and def.metadata ~= nil and def.metadata.race == "goblin"
    end)
    if goblin_card == nil then
        battle.dlog("[ability] back_stab: error - no untriggered goblin character in " .. front_line_key)
        return {}, "back_stab requires untriggered goblin character in front_line"
    end
    goblin_card.trigger = true

    if defender.inventory_item_id == goblin_card.inventory_item_id then
        battle.dlog("[ability] back_stab: error - defender matches selected goblin id=" .. tostring(goblin_card.inventory_item_id))
        return {}, "back_stab cannot target the selected goblin"
    end

    local line_key = (event_data or {}).defender_line_key
    local void_key = (event_data or {}).defender_side_void
    local defender_line = line_key ~= nil and state[line_key] or nil

    local source_item_def = helpers.find_item_def(state.item_defs, source_card.item_definition_code_name)
    local atk_add = 0
    if source_item_def ~= nil then
        if source_item_def.base_stats ~= nil and source_item_def.base_stats.atk_add then
            atk_add = source_item_def.base_stats.atk_add
        elseif source_item_def.metadata ~= nil and source_item_def.metadata.atk_add then
            atk_add = source_item_def.metadata.atk_add
        end
    end

    local goblin_item_def = helpers.find_item_def(state.item_defs, goblin_card.item_definition_code_name)
    local char_atk = (goblin_item_def ~= nil and goblin_item_def.base_stats ~= nil and goblin_item_def.base_stats.atk) or 1
    local damage = atk_add + char_atk
    battle.dlog("[ability] back_stab: goblin=" .. goblin_card.inventory_item_id .. " target=" .. defender.inventory_item_id .. " damage=" .. damage)

    local expose_action = helpers.expose_ability_selected_card(state, goblin_card)
    local ability_actions = {
        expose_action,
        source_side .. "_card_ability:source=" .. source_card.inventory_item_id .. ",ability=back_stab,target=" .. defender.inventory_item_id .. ",selected=" .. goblin_card.inventory_item_id
    }
    local damage_actions, dmg_err = helpers.deal_damage_to_character(state, goblin_card, defender, damage, defender_line, void_key)
    if dmg_err ~= nil then return ability_actions, dmg_err end
    for _, action in ipairs(damage_actions) do
        table.insert(ability_actions, action)
    end
    return ability_actions, nil
end

-- ability: holy_glow
function holy_glow_execute(state, source_card, event_data, helpers)
    local battle = helpers.lib_battle_common
    battle.dlog("== [ability] holy_glow ====================")

    local caster_side = helpers.find_card_side(state, source_card)
    if caster_side == "unknown" or caster_side == nil then
        local function find_side_in_all_zones(card_id)
            local alpha_keys = { "alpha_front_line", "alpha_back_line", "alpha_hand", "alpha_the_void", "alpha_the_source" }
            for _, key in ipairs(alpha_keys) do
                if state[key] then
                    for _, c in ipairs(state[key]) do
                        if c.inventory_item_id == card_id then return "alpha" end
                    end
                end
            end
            local omega_keys = { "omega_front_line", "omega_back_line", "omega_hand", "omega_the_void", "omega_the_source" }
            for _, key in ipairs(omega_keys) do
                if state[key] then
                    for _, c in ipairs(state[key]) do
                        if c.inventory_item_id == card_id then return "omega" end
                    end
                end
            end
            return "alpha" -- fallback
        end
        caster_side = find_side_in_all_zones(source_card.inventory_item_id)
    end

    local frontline_key = caster_side .. "_front_line"
    local front_line = state[frontline_key] or {}
    local elf_card = helpers.find_untriggered_card(front_line, function(c)
        local def = helpers.find_item_def(state.item_defs, c.item_definition_code_name)
        return def ~= nil and def.metadata ~= nil and def.metadata.race == "light_elf"
    end)

    if elf_card == nil then
        battle.dlog("[ability] holy_glow: error - no untriggered light_elf character in " .. frontline_key)
        return {}, "holy_glow requires an untriggered light_elf character in front_line"
    end

    elf_card.trigger = true
    local expose_action = helpers.expose_ability_selected_card(state, elf_card)

    local hp_key = caster_side .. "_hp"
    local max_hp_key = caster_side .. "_max_hp"

    -- Ensure max HP is declared for the battle
    if state.alpha_max_hp == nil then
        state.alpha_max_hp = state.alpha_hp
    end
    if state.omega_max_hp == nil then
        state.omega_max_hp = state.omega_hp
    end

    local card_def = helpers.find_item_def(state.item_defs, source_card.item_definition_code_name)
    local hp_restore = 0
    if card_def ~= nil and card_def.base_stats ~= nil and card_def.base_stats.hp_restore ~= nil then
        hp_restore = card_def.base_stats.hp_restore
    end

    local current_hp = state[hp_key] or 0
    local max_hp = state[max_hp_key] or current_hp
    local new_hp = current_hp + hp_restore
    if new_hp > max_hp then
        new_hp = max_hp
    end
    local actual_restored = new_hp - current_hp
    state[hp_key] = new_hp

    local is_ability_card = (card_def ~= nil and card_def.metadata ~= nil and card_def.metadata.type == "ability")
    local will_system_send_to_void = false
    if is_ability_card then
        local defender_line_key = event_data ~= nil and event_data.defender_line_key or nil
        if defender_line_key == "alpha_front_line" or
           defender_line_key == "alpha_back_line"  or
           defender_line_key == "omega_front_line" or
           defender_line_key == "omega_back_line" then
            will_system_send_to_void = true
        end
    end

    battle.dlog("[ability] holy_glow: caster=" .. source_card.inventory_item_id .. " side=" .. caster_side .. " light_elf=" .. elf_card.inventory_item_id .. " restore=" .. hp_restore .. " actual_restored=" .. actual_restored .. " new_hp=" .. new_hp .. "/" .. max_hp .. " will_system_send_to_void=" .. tostring(will_system_send_to_void))

    if not will_system_send_to_void then
        -- Move source card to the void
        local lines_to_check = {
            caster_side .. "_front_line",
            caster_side .. "_back_line",
            caster_side .. "_hand"
        }
        for _, line_key in ipairs(lines_to_check) do
            local line = state[line_key]
            if line ~= nil then
                battle.remove_card_from_line(line, source_card.inventory_item_id)
            end
        end

        local void_key = caster_side .. "_the_void"
        if state[void_key] == nil then state[void_key] = {} end
        table.insert(state[void_key], source_card)
        battle.dlog("[ability] holy_glow: source card sent to void=" .. void_key .. " id=" .. source_card.inventory_item_id)
    end

    local ability_actions = {}
    if expose_action ~= nil then
        table.insert(ability_actions, expose_action)
    end
    table.insert(ability_actions, caster_side .. "_card_ability:source=" .. source_card.inventory_item_id .. ",ability=holy_glow,hp_restore=" .. hp_restore .. ",actual_restored=" .. actual_restored .. "," .. hp_key .. "=" .. state[hp_key] .. ",selected=" .. elf_card.inventory_item_id)
    
    if not will_system_send_to_void then
        table.insert(ability_actions, caster_side .. "_card_sent_to_void:" .. source_card.inventory_item_id)
    end

    return ability_actions, nil
end
