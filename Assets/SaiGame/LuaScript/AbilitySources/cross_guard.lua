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
