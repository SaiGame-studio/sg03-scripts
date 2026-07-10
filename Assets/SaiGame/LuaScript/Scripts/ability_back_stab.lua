-- ability_back_stab  (is_library = true)

function execute(state, source_card, event_data, helpers)
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
