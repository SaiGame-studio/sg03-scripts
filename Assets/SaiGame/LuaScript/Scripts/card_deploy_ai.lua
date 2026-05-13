require "lib_battle_common"

-- card_deploy_ai
-- AI-controlled omega deployment script.
-- Routes deploy strategy based on state.metadata.enemy_entity_key.
-- Each enemy key maps to a dedicated deploy function for a unique playstyle.
-- Unknown keys fall back to the difficulty-based deploy in lib_battle_ai.
--
-- Endpoint: POST /api/v1/games/{game_id}/scripts/card_deploy_ai/run
-- Payload (all optional):
-- {
--   "session_id": "battle-session-uuid"
-- }

local SLOT_COUNT = 5

local collect_omega_hand_cards     -- forward declaration
local split_omega_cards_by_type    -- forward declaration
local deploy_one_card_to_line      -- forward declaration
local rebuild_omega_hand           -- forward declaration
local append_omega_deploy_actions  -- forward declaration
local apply_omega_deploy_result    -- forward declaration
local deploy_goblin_shaman         -- forward declaration
local enemy_deploy_dispatch        -- table: enemy_entity_key → deploy function (populated after enemy functions)

local function main()
    local session_id, sid_err = lib_battle_common.resolve_session_id()
    if sid_err ~= nil then output.error = sid_err ; return end

    local state, load_err = lib_battle_common.load_session(session_id)
    if load_err ~= nil then output.error = load_err ; return end

    if state.omega_hand == nil or #state.omega_hand == 0 then
        output.error = "omega_hand is empty; run init_cards first"
        return
    end

    local enemy_key = state.metadata ~= nil and state.metadata.enemy_entity_key or nil
    lib_battle_common.dlog("[card_deploy_ai] enemy_entity_key=" .. tostring(enemy_key))

    local deploy_fn = enemy_key ~= nil and enemy_deploy_dispatch[enemy_key] or nil
    if deploy_fn == nil then
        output.error = "no deploy handler for enemy_entity_key: " .. tostring(enemy_key)
        return
    end

    local o_front, o_back, o_hand, deploy_err = deploy_fn(state)
    if deploy_err ~= nil then output.error = deploy_err ; return end

    local apply_err = apply_omega_deploy_result(session_id, state, o_front, o_back, o_hand)
    if apply_err ~= nil then output.error = apply_err ; return end
end

-- ─── Card helpers ─────────────────────────────────────────────────────────────

-- Returns the list of real (non-empty) cards from omega_hand.
collect_omega_hand_cards = function(omega_hand)
    local hand_cards = {}
    for _, hand_slot in ipairs(omega_hand) do
        if hand_slot.item_definition_code_name ~= nil and hand_slot.item_definition_code_name ~= "" then
            table.insert(hand_cards, hand_slot)
        end
    end
    return hand_cards
end

-- Splits hand_cards into character_cards (front-eligible) and other_cards (back only).
split_omega_cards_by_type = function(item_defs, hand_cards)
    local character_cards = {}
    local other_cards     = {}
    for _, hand_card in ipairs(hand_cards) do
        if lib_battle_common.check_card_type(item_defs, hand_card, "character") then
            table.insert(character_cards, hand_card)
        else
            table.insert(other_cards, hand_card)
        end
    end
    return character_cards, other_cards
end

-- Places deploy_card into the first empty slot of target_line with given face_up.
-- Records the card id into deployed_ids and the card into deployed_list.
-- Returns true if a slot was found, false otherwise.
deploy_one_card_to_line = function(target_line, deploy_card, face_up, deployed_ids, deployed_list)
    for slot_i = 1, SLOT_COUNT do
        local existing_slot = target_line[slot_i]
        if existing_slot == nil or existing_slot.item_definition_code_name == nil or existing_slot.item_definition_code_name == "" then
            deploy_card.slot_index = slot_i - 1
            deploy_card.face_up    = face_up
            deploy_card.expose     = face_up
            target_line[slot_i]    = deploy_card
            table.insert(deployed_ids, deploy_card.id)
            table.insert(deployed_list, deploy_card)
            return true
        end
    end
    return false
end

-- Rebuilds a SLOT_COUNT-slot hand, omitting cards whose id appears in deployed_ids.
rebuild_omega_hand = function(original_hand, deployed_ids)
    local removed_set = {}
    for _, deployed_id in ipairs(deployed_ids) do removed_set[deployed_id] = true end

    local new_hand  = {}
    local hand_slot = 1
    for _, hand_card in ipairs(original_hand) do
        if hand_slot > SLOT_COUNT then break end
        local hand_card_id = hand_card.id
        if hand_card_id ~= nil and hand_card_id ~= "" and not removed_set[hand_card_id] then
            hand_card.slot_index = hand_slot - 1
            new_hand[hand_slot]  = hand_card
            hand_slot            = hand_slot + 1
        end
    end
    for fill_slot = hand_slot, SLOT_COUNT do new_hand[fill_slot] = {} end
    return new_hand
end

-- Appends omega_hand_to_front_line / omega_hand_to_back_line client actions.
append_omega_deploy_actions = function(state, front_deployed, back_deployed)
    for _, front_card in ipairs(front_deployed) do
        if front_card.inventory_item_id ~= nil and front_card.inventory_item_id ~= "" then
            lib_battle_common.append_client_action(state, "omega_hand_to_front_line:" .. front_card.inventory_item_id .. "," .. (front_card.slot_index or 0))
        end
    end
    for _, back_card in ipairs(back_deployed) do
        if back_card.inventory_item_id ~= nil and back_card.inventory_item_id ~= "" then
            lib_battle_common.append_client_action(state, "omega_hand_to_back_line:" .. back_card.inventory_item_id .. "," .. (back_card.slot_index or 0))
        end
    end
end

-- Applies o_front / o_back / o_hand onto state, resets turn data, and saves the session.
-- Returns err or nil.
apply_omega_deploy_result = function(session_id, state, o_front, o_back, o_hand)
    state.omega_front_line = o_front
    state.omega_back_line  = o_back
    state.omega_hand       = o_hand

    for _, deployed_front_card in ipairs(o_front) do
        lib_battle_common.reset_card_turn_state(state.item_defs, deployed_front_card)
    end
    for _, deployed_back_card in ipairs(o_back) do
        lib_battle_common.reset_card_turn_state(state.item_defs, deployed_back_card)
    end

    state.action     = (state.action or 0) + 1
    state.updated_at = ctx.timestamp
    if state.metadata == nil then state.metadata = {} end
    state.metadata.next_move = "alpha_turn"

    local save_err = game.battle_session_update(session_id, state)
    if save_err ~= nil then return save_err end

    lib_battle_common.battle_status()
    output.client_actions = state.client_actions
    return nil
end

-- ─── Enemy-specific deploy strategies ────────────────────────────────────────

-- Goblin Shaman strategy:
--   Front : 1 character, always face-down (warriors hidden behind ritual magic).
--   Back  : up to 2 non-characters, always face-up (shaman spells openly displayed).
deploy_goblin_shaman = function(state)
    lib_battle_common.dlog("[card_deploy_ai] == deploy_goblin_shaman ==")

    local omega_front_line = state.omega_front_line or {}
    local omega_back_line  = state.omega_back_line  or {}
    local deployed_ids     = {}
    local front_deployed   = {}
    local back_deployed    = {}

    local hand_cards                   = collect_omega_hand_cards(state.omega_hand)
    local character_cards, other_cards = split_omega_cards_by_type(state.item_defs, hand_cards)
    lib_battle_common.dlog("[card_deploy_ai] goblin_shaman: characters=" .. #character_cards .. " others=" .. #other_cards)

    if #character_cards >= 1 then
        deploy_one_card_to_line(omega_front_line, character_cards[1], false, deployed_ids, front_deployed)
    end

    local back_deploy_count = 0
    for _, other_card in ipairs(other_cards) do
        if back_deploy_count >= 2 then break end
        local was_deployed = deploy_one_card_to_line(omega_back_line, other_card, true, deployed_ids, back_deployed)
        if was_deployed then back_deploy_count = back_deploy_count + 1 end
    end

    local new_omega_hand = rebuild_omega_hand(state.omega_hand, deployed_ids)
    append_omega_deploy_actions(state, front_deployed, back_deployed)
    lib_battle_common.dlog("[card_deploy_ai] goblin_shaman: deployed " .. #deployed_ids .. " card(s)")

    return omega_front_line, omega_back_line, new_omega_hand, nil
end

-- ─── Dispatch table ────────────────────────────────────────────────────────────
-- Maps enemy_entity_key → deploy function.
-- Add a new entry here when a new enemy deploy strategy is implemented above.

enemy_deploy_dispatch = {
    goblin_shaman = deploy_goblin_shaman,
}

main()