local M = {
    event = "on_attack",
    target_positions = { "enemy_frontline" },
}

function M.execute(state, attacker_card, event_data, helpers)
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

return M
