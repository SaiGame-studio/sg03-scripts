-- lib_battle_entity_ai  (is_library = true)
-- Per-enemy AI logic: defend reactions and deploy strategies.
-- Each enemy entity exposes:
--   <entity>.defend(state)  → err or nil
--   <entity>.deploy(state)  → front_line, back_line, hand, err
--
-- Usage:
--   require "lib_battle_entity_ai"
--   local err = lib_battle_entity_ai.goblin_shaman.defend(state)
--   local o_front, o_back, o_hand, err = lib_battle_entity_ai.goblin_shaman.deploy(state)
--
-- Depends on: lib_battle_common, lib_battle_ai, lib_card_ability

-- ─── Shared helpers ──────────────────────────────────────────────────────────

-- Searches back_line for cards matching code_name.
-- Returns the first exposed card (expose==true) if found; otherwise the first unexposed card.
-- Returns nil if no match exists.
local function find_back_line_card_prefer_exposed(back_line, code_name)
    lib_battle_common.dlog("[entity_ai] searching back_line (count=" .. #back_line .. ") for code=" .. code_name .. " (prefer exposed)")
    local unexposed_fallback = nil
    for _, back_card in ipairs(back_line) do
        local card_id      = back_card.inventory_item_id or ""
        local card_code    = back_card.item_definition_code_name or ""
        local card_exposed = back_card.expose == true
        lib_battle_common.dlog("[entity_ai] checking back_line card: id=" .. card_id .. " code=" .. card_code .. " expose=" .. tostring(back_card.expose))
        if card_id == "" then
            lib_battle_common.dlog("[entity_ai] skip: no inventory_item_id")
        elseif card_code ~= code_name then
            lib_battle_common.dlog("[entity_ai] skip: code mismatch (want=" .. code_name .. ")")
        elseif card_exposed then
            lib_battle_common.dlog("[entity_ai] found exposed match: id=" .. card_id)
            return back_card
        else
            lib_battle_common.dlog("[entity_ai] found unexposed match (saved as fallback): id=" .. card_id)
            if unexposed_fallback == nil then
                unexposed_fallback = back_card
            end
        end
    end
    if unexposed_fallback ~= nil then
        lib_battle_common.dlog("[entity_ai] using unexposed fallback: id=" .. unexposed_fallback.inventory_item_id)
    end
    return unexposed_fallback
end

-- Returns true if pending_attack targets a card on omega_front_line AND deals positive damage.
local function is_omega_front_line_taking_damage(state)
    local pending_atk = state.pending_attack
    if pending_atk == nil then
        lib_battle_common.dlog("[entity_ai] is_omega_front_line_taking_damage: no pending_attack")
        return false
    end
    local damage = pending_atk.damage_dealt or 0
    if damage <= 0 then
        lib_battle_common.dlog("[entity_ai] is_omega_front_line_taking_damage: damage_dealt=" .. damage .. " (no damage)")
        return false
    end
    local defender_id      = pending_atk.defender_inventory_item_id or ""
    local omega_front_line = state.omega_front_line or {}
    for _, front_card in ipairs(omega_front_line) do
        if front_card.inventory_item_id == defender_id then
            lib_battle_common.dlog("[entity_ai] is_omega_front_line_taking_damage: defender=" .. defender_id .. " on omega_front_line damage=" .. damage)
            return true
        end
    end
    lib_battle_common.dlog("[entity_ai] is_omega_front_line_taking_damage: defender=" .. defender_id .. " not on omega_front_line, skip")
    return false
end

-- Triggers an on_defend ability on source_card, appends resulting actions into state.
-- Returns err or nil.
local function trigger_defend_ability(state, source_card, ability_key)
    local source_item_def = nil
    if state.item_defs ~= nil then
        for _, item_def in ipairs(state.item_defs) do
            if item_def.item_code == ability_key then
                source_item_def = item_def
                break
            end
        end
    end
    local def_add = (source_item_def ~= nil and source_item_def.base_stats and source_item_def.base_stats.def_add) or 0
    lib_battle_common.dlog("[entity_ai] trigger_defend_ability: id=" .. source_card.inventory_item_id .. " ability=" .. ability_key .. " def_add=" .. def_add)
    lib_battle_common.dlog("[entity_ai] pending_attack.damage_dealt=" .. tostring(state.pending_attack ~= nil and state.pending_attack.damage_dealt or "nil"))
    local defend_event_data = {}
    defend_event_data.pending_attack = state.pending_attack
    local ability_actions, ability_err = lib_card_ability.trigger_ability_by_key(state, source_card, ability_key, "on_defend", defend_event_data)
    if ability_err ~= nil then
        lib_battle_common.dlog("[entity_ai] ability error: " .. ability_err)
        return ability_err
    end
    lib_battle_common.dlog("[entity_ai] ability_actions count=" .. #ability_actions)
    for _, ability_action in ipairs(ability_actions) do
        lib_battle_common.append_client_action(state, ability_action)
    end
    return nil
end

-- Logs the final_def of every card in the given front line (for post-buff inspection).
local function log_front_line_def(front_line, label)
    lib_battle_common.dlog("[entity_ai] " .. label .. " front_line def (count=" .. #front_line .. "):")
    for _, front_card in ipairs(front_line) do
        local front_id   = front_card.inventory_item_id or ""
        local front_code = front_card.item_definition_code_name or ""
        local front_def  = front_card.final_def or 0
        lib_battle_common.dlog("[entity_ai]   id=" .. front_id .. " code=" .. front_code .. " final_def=" .. front_def)
    end
end

-- Filters a card list, returning only cards with code_name == "totem_pulse".
local function filter_totem_pulse_cards(other_cards)
    local totem_pulse_cards = {}
    for _, other_card in ipairs(other_cards) do
        if other_card.item_definition_code_name == "totem_pulse" then
            table.insert(totem_pulse_cards, other_card)
        end
    end
    return totem_pulse_cards
end

-- ─── goblin_shaman ────────────────────────────────────────────────────────────

-- Defend reaction: trigger totem_pulse from back_line if omega front-line is taking damage.
-- Returns err or nil.
function goblin_shaman_defend(state)
    lib_battle_common.dlog("[entity_ai] == goblin_shaman.defend ==")
    if not is_omega_front_line_taking_damage(state) then
        lib_battle_common.dlog("[entity_ai] goblin_shaman.defend: attack does not damage omega front-line, skip totem")
        return nil
    end
    local omega_back_line = state.omega_back_line or {}
    local totem_card = find_back_line_card_prefer_exposed(omega_back_line, "totem_pulse")
    if totem_card == nil then
        lib_battle_common.dlog("[entity_ai] goblin_shaman.defend: no totem_pulse in back_line, skip")
        return nil
    end
    local ability_err = trigger_defend_ability(state, totem_card, "totem_pulse")
    if ability_err ~= nil then return ability_err end
    log_front_line_def(state.omega_front_line or {}, "omega")
    lib_battle_common.dlog("[entity_ai] goblin_shaman.defend done")
    return nil
end

-- Deploy strategy: one character (random face_up) to front, all totem_pulse cards (random face_up each) to back.
-- Resets newly deployed cards. Returns: front_line, back_line, hand, err.
function goblin_shaman_deploy(state)
    lib_battle_common.dlog("[entity_ai] == goblin_shaman.deploy ==")

    local SLOT_COUNT       = lib_battle_common.get_hand_size()
    local omega_front_line = state.omega_front_line or {}
    local omega_back_line  = state.omega_back_line  or {}
    local deployed_ids     = {}
    local front_deployed   = {}
    local back_deployed    = {}

    local hand_cards                   = lib_battle_ai._collect_cards(state.omega_hand or {})
    local character_cards, other_cards = lib_battle_ai._split_cards_by_type(hand_cards, state.item_defs)
    local totem_pulse_cards            = filter_totem_pulse_cards(other_cards)
    lib_battle_common.dlog("[entity_ai] goblin_shaman.deploy: characters=" .. #character_cards .. " totem_pulse=" .. #totem_pulse_cards)

    -- Deploy one character to front (random face_up).
    if #character_cards >= 1 then
        local deploy_card = character_cards[1]
        local face_up = math.random(0, 1) == 1
        for slot_i = 1, SLOT_COUNT do
            local existing = omega_front_line[slot_i]
            if existing == nil or existing.item_definition_code_name == nil or existing.item_definition_code_name == "" then
                deploy_card.slot_index   = slot_i - 1
                deploy_card.face_up      = face_up
                deploy_card.expose       = face_up
                omega_front_line[slot_i] = deploy_card
                table.insert(deployed_ids, deploy_card.id)
                table.insert(front_deployed, deploy_card)
                lib_battle_common.dlog("[entity_ai] goblin_shaman.deploy: front slot=" .. (slot_i - 1) .. " card=" .. (deploy_card.inventory_item_id or "?"))
                break
            end
        end
    end

    -- Deploy totem_pulse cards to back (random face_up each).
    for _, deploy_card in ipairs(totem_pulse_cards) do
        local face_up = math.random(0, 1) == 1
        for slot_i = 1, SLOT_COUNT do
            local existing = omega_back_line[slot_i]
            if existing == nil or existing.item_definition_code_name == nil or existing.item_definition_code_name == "" then
                deploy_card.slot_index  = slot_i - 1
                deploy_card.face_up     = face_up
                deploy_card.expose      = face_up
                omega_back_line[slot_i] = deploy_card
                table.insert(deployed_ids, deploy_card.id)
                table.insert(back_deployed, deploy_card)
                lib_battle_common.dlog("[entity_ai] goblin_shaman.deploy: back slot=" .. (slot_i - 1) .. " card=" .. (deploy_card.inventory_item_id or "?"))
                break
            end
        end
    end

    local new_hand = lib_battle_ai._rebuild_hand(state.omega_hand or {}, deployed_ids)
    lib_battle_ai._append_mid_deploy_actions(state, front_deployed, back_deployed)
    lib_battle_ai._reset_deployed_cards(state.item_defs, front_deployed, back_deployed)
    lib_battle_common.dlog("[entity_ai] goblin_shaman.deploy: deployed=" .. #deployed_ids)

    return omega_front_line, omega_back_line, new_hand, nil
end

-- Attack planning: select targets on alpha's field for omega to attack next turn.
-- Returns err or nil.
function goblin_shaman_plan_attack(state)
    lib_battle_common.dlog("[entity_ai] == goblin_shaman_plan_attack ==")
    local plan_err = lib_battle_ai.omega_planning_to_attack(state)
    if plan_err ~= nil then return plan_err end
    return nil
end


