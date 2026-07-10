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
