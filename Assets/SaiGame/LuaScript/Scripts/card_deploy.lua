require "lib_battle_common"

-- card_deploy
-- Finalizes the opening deploy for both alpha (player) and omega (enemy AI).
-- Alpha's card placement is read from the payload; omega's strategy is determined
-- by state.metadata.enemy_entity_key and routed to an enemy-specific deploy function.
--
-- Endpoint: POST /api/v1/games/{game_id}/scripts/card_deploy/run
-- Example payload (session_id is optional; omit to use the current active session):
-- {
--   "session_id": "battle-session-uuid",
--   "hand":       ["inventory-item-id-6", "", "inventory-item-id-7", "", ""],
--   "front_line": [{"inventory_item_id": "inventory-item-id-1", "face_up": false, "slot_index": 0}, ...],
--   "back_line":  [{"inventory_item_id": "inventory-item-id-3", "face_up": true,  "slot_index": 2}, ...]
-- }
-- face_up=true  → card.face_up=true,  card.expose=true
-- face_up=false → card.face_up=false, card.expose=false
-- slot_index (0-based) determines which position the card occupies in the line;
--   card.slot_index is updated to match.
-- hand is a positional array (array index − 1 = slot); card.slot_index is updated accordingly.
-- Verified by comparing exact inventory_item_id sets: union of payload
-- (hand + front_line + back_line) must match union of state
-- (alpha_hand + alpha_front_line + alpha_back_line) — no item may appear
-- or disappear.

local SLOT_COUNT = 5

local validate_payload                   -- forward declaration
local build_lines                        -- forward declaration
local verify_card_sets                   -- forward declaration
local check_front_line_limit             -- forward declaration
local build_remaining_hand               -- forward declaration
local append_alpha_deploy_client_actions -- forward declaration
local collect_omega_hand_cards           -- forward declaration
local split_omega_cards_by_type          -- forward declaration
local deploy_one_card_to_line            -- forward declaration
local rebuild_omega_hand                 -- forward declaration
local append_omega_deploy_actions        -- forward declaration
local apply_omega_deploy_result          -- forward declaration
local deploy_goblin_shaman               -- forward declaration
local enemy_deploy_dispatch              -- table: enemy_entity_key → deploy function (populated after enemy functions)
local load_battle_state                  -- forward declaration
local run_alpha_deploy                   -- forward declaration
local run_omega_deploy                   -- forward declaration

local function max_front_deploy_per_turn()
    return 1
end

local function main()
    local session_id, state, load_err = load_battle_state()
    if load_err ~= nil then output.error = load_err ; return end

    local alpha_err = run_alpha_deploy(state)
    if alpha_err ~= nil then output.error = alpha_err ; return end

    lib_battle_common.append_client_action(state, "omega_take_lamp")

    local omega_err = run_omega_deploy(session_id, state)
    if omega_err ~= nil then output.error = omega_err ; return end
end

-- ─── Main orchestration helpers ─────────────────────────────────────────────

-- Validates payload, resolves session, loads state, and checks both hands.
-- Returns session_id, state, err.
load_battle_state = function()
    local val_err = validate_payload()
    if val_err ~= nil then return nil, nil, val_err end

    local session_id, sid_err = lib_battle_common.resolve_session_id()
    if sid_err ~= nil then return nil, nil, sid_err end

    local state, state_err = lib_battle_common.load_session(session_id)
    if state_err ~= nil then return nil, nil, state_err end

    if state.alpha_hand == nil or #state.alpha_hand == 0 then
        return nil, nil, "alpha_hand is empty; run init_cards first"
    end
    if state.omega_hand == nil or #state.omega_hand == 0 then
        return nil, nil, "omega_hand is empty; run init_cards first"
    end
    return session_id, state, nil
end

-- Verifies card sets, enforces front-line limit, builds and applies alpha lines.
-- Returns err or nil.
run_alpha_deploy = function(state)
    local verify_err = verify_card_sets(state)
    if verify_err ~= nil then return verify_err end

    local limit_err = check_front_line_limit(state)
    if limit_err ~= nil then return limit_err end

    local front_line, back_line, build_err = build_lines(state.alpha_hand)
    if build_err ~= nil then return build_err end

    state.alpha_hand       = build_remaining_hand(state.alpha_hand)
    state.alpha_front_line = front_line
    state.alpha_back_line  = back_line

    for _, deployed_card in ipairs(front_line) do
        lib_battle_common.reset_card_turn_state(state.item_defs, deployed_card)
    end
    for _, deployed_card in ipairs(back_line) do
        lib_battle_common.reset_card_turn_state(state.item_defs, deployed_card)
    end

    append_alpha_deploy_client_actions(state, front_line, back_line)
    return nil
end

-- Dispatches to the enemy-specific deploy function and applies the result.
-- Returns err or nil.
run_omega_deploy = function(session_id, state)
    local enemy_key = state.metadata ~= nil and state.metadata.enemy_entity_key or nil
    lib_battle_common.dlog("[card_deploy] enemy_entity_key=" .. tostring(enemy_key))

    local deploy_fn = enemy_key ~= nil and enemy_deploy_dispatch[enemy_key] or nil
    if deploy_fn == nil then
        return "no deploy handler for enemy_entity_key: " .. tostring(enemy_key)
    end

    local o_front, o_back, o_hand, deploy_err = deploy_fn(state)
    if deploy_err ~= nil then return deploy_err end

    return apply_omega_deploy_result(session_id, state, o_front, o_back, o_hand)
end

-- ─── Alpha deploy helpers ─────────────────────────────────────────────────────

validate_payload = function()
    if payload.hand == nil then
        return "hand is required"
    end
    if type(payload.hand) ~= "table" then
        return "hand must be an array of inventory_item_ids"
    end
    if payload.front_line ~= nil and type(payload.front_line) ~= "table" then
        return "front_line must be an array of inventory_item_ids"
    end
    if payload.back_line ~= nil and type(payload.back_line) ~= "table" then
        return "back_line must be an array of inventory_item_ids"
    end
    local seen = {}
    for i, inventory_item_id in ipairs(payload.hand) do
        if type(inventory_item_id) ~= "string" then
            return "hand[" .. i .. "] must be a string"
        end
        if inventory_item_id ~= "" then
            if seen[inventory_item_id] then
                return "duplicate inventory_item_id in hand: " .. inventory_item_id
            end
            seen[inventory_item_id] = "hand"
        end
    end
    for i, slot in ipairs(payload.front_line or {}) do
        if type(slot) ~= "table" then
            return "front_line[" .. i .. "] must be an object"
        end
        local inventory_item_id = slot.inventory_item_id
        if type(inventory_item_id) ~= "string" then
            return "front_line[" .. i .. "].inventory_item_id must be a string"
        end
        if type(slot.slot_index) ~= "number" or slot.slot_index < 0 or slot.slot_index >= SLOT_COUNT then
            return "front_line[" .. i .. "].slot_index must be an integer in [0, " .. (SLOT_COUNT - 1) .. "]"
        end
        if inventory_item_id ~= "" then
            if seen[inventory_item_id] then
                return "inventory_item_id " .. inventory_item_id .. " appears in both hand and front_line"
            end
            seen[inventory_item_id] = "front_line"
        end
    end
    for i, slot in ipairs(payload.back_line or {}) do
        if type(slot) ~= "table" then
            return "back_line[" .. i .. "] must be an object"
        end
        local inventory_item_id = slot.inventory_item_id
        if type(inventory_item_id) ~= "string" then
            return "back_line[" .. i .. "].inventory_item_id must be a string"
        end
        if type(slot.slot_index) ~= "number" or slot.slot_index < 0 or slot.slot_index >= SLOT_COUNT then
            return "back_line[" .. i .. "].slot_index must be an integer in [0, " .. (SLOT_COUNT - 1) .. "]"
        end
        if inventory_item_id ~= "" then
            if seen[inventory_item_id] then
                return "inventory_item_id " .. inventory_item_id .. " appears in " .. seen[inventory_item_id] .. " and back_line"
            end
            seen[inventory_item_id] = "back_line"
        end
    end
    return nil
end

-- Resolves each requested card ID against alpha_hand and returns two card lists.
-- Returns nil, nil, err on the first ID that is not found in the hand.
build_lines = function(alpha_hand)
    local hand_index = {}
    for _, card in ipairs(alpha_hand) do
        if card.inventory_item_id ~= nil and card.inventory_item_id ~= "" then
            hand_index[card.inventory_item_id] = card
        end
    end

    local front_line = {}
    for i = 1, SLOT_COUNT do front_line[i] = {} end
    for i, slot in ipairs(payload.front_line or {}) do
        local inventory_item_id = slot.inventory_item_id
        if inventory_item_id ~= nil and inventory_item_id ~= "" then
            local card = hand_index[inventory_item_id]
            if card == nil then
                return nil, nil, "front_line[" .. i .. "] card (" .. inventory_item_id .. ") not found in alpha_hand"
            end
            local face_up = slot.face_up == true
            card.face_up     = face_up
            card.expose      = face_up
            card.slot_index  = slot.slot_index
            front_line[slot.slot_index + 1] = card
        end
    end

    local back_line = {}
    for i = 1, SLOT_COUNT do back_line[i] = {} end
    for i, slot in ipairs(payload.back_line or {}) do
        local inventory_item_id = slot.inventory_item_id
        if inventory_item_id ~= nil and inventory_item_id ~= "" then
            local card = hand_index[inventory_item_id]
            if card == nil then
                return nil, nil, "back_line[" .. i .. "] card (" .. inventory_item_id .. ") not found in alpha_hand"
            end
            local face_up = slot.face_up == true
            card.face_up     = face_up
            card.expose      = face_up
            card.slot_index  = slot.slot_index
            back_line[slot.slot_index + 1] = card
        end
    end

    return front_line, back_line, nil
end

-- Cross-verifies that payload IDs (hand + front_line + back_line) exactly match
-- state IDs (alpha_hand + alpha_front_line + alpha_back_line). Returns err or nil.
verify_card_sets = function(state)
    local payload_ids = {}
    for _, inventory_item_id in ipairs(payload.hand) do
        if inventory_item_id ~= "" then payload_ids[inventory_item_id] = true end
    end
    for _, slot in ipairs(payload.front_line or {}) do
        local inventory_item_id = slot.inventory_item_id
        if inventory_item_id ~= nil and inventory_item_id ~= "" then payload_ids[inventory_item_id] = true end
    end
    for _, slot in ipairs(payload.back_line or {}) do
        local inventory_item_id = slot.inventory_item_id
        if inventory_item_id ~= nil and inventory_item_id ~= "" then payload_ids[inventory_item_id] = true end
    end

    local state_ids = {}
    for _, card in ipairs(state.alpha_hand) do
        if card.inventory_item_id ~= nil and card.inventory_item_id ~= "" then state_ids[card.inventory_item_id] = true end
    end
    for _, card in ipairs(state.alpha_front_line or {}) do
        if card.inventory_item_id ~= nil and card.inventory_item_id ~= "" then state_ids[card.inventory_item_id] = true end
    end
    for _, card in ipairs(state.alpha_back_line or {}) do
        if card.inventory_item_id ~= nil and card.inventory_item_id ~= "" then state_ids[card.inventory_item_id] = true end
    end

    for inventory_item_id, _ in pairs(payload_ids) do
        if not state_ids[inventory_item_id] then
            return "payload item (" .. inventory_item_id .. ") does not exist in battle state"
        end
    end
    for inventory_item_id, _ in pairs(state_ids) do
        if not payload_ids[inventory_item_id] then
            return "state item (" .. inventory_item_id .. ") is missing from payload"
        end
    end
    return nil
end

-- Enforces at most 1 new card deployed to front_line per turn. Returns err or nil.
check_front_line_limit = function(state)
    local existing_front_ids = {}
    for _, card in ipairs(state.alpha_front_line or {}) do
        if card.inventory_item_id ~= nil and card.inventory_item_id ~= "" then
            existing_front_ids[card.inventory_item_id] = true
        end
    end
    local new_front_count = 0
    for _, slot in ipairs(payload.front_line or {}) do
        local inventory_item_id = slot.inventory_item_id
        if inventory_item_id ~= nil and inventory_item_id ~= "" and not existing_front_ids[inventory_item_id] then
            new_front_count = new_front_count + 1
        end
    end
    if new_front_count > max_front_deploy_per_turn() then
        return "only " .. max_front_deploy_per_turn() .. " new card may be deployed to front_line per turn (" .. new_front_count .. " new cards received)"
    end
    return nil
end

-- Rebuilds alpha_hand from payload.hand, preserving slot positions.
-- Missing or empty-string slots become {} (empty slot marker).
build_remaining_hand = function(alpha_hand)
    local hand_index = {}
    for _, card in ipairs(alpha_hand) do
        if card.inventory_item_id ~= nil and card.inventory_item_id ~= "" then
            hand_index[card.inventory_item_id] = card
        end
    end
    local remaining_hand = {}
    for i = 1, SLOT_COUNT do
        local inventory_item_id = payload.hand[i]
        if inventory_item_id ~= nil and inventory_item_id ~= "" then
            local card = hand_index[inventory_item_id]
            card.slot_index = i - 1
            remaining_hand[i] = card
        else
            remaining_hand[i] = {}
        end
    end
    return remaining_hand
end

-- Appends client actions for all alpha card movements.
append_alpha_deploy_client_actions = function(state, front_line, back_line)
    for _, alpha_front_card in ipairs(front_line) do
        if alpha_front_card.inventory_item_id ~= nil and alpha_front_card.inventory_item_id ~= "" then
            lib_battle_common.append_client_action(state, "alpha_hand_to_front_line:" .. alpha_front_card.inventory_item_id .. "," .. (alpha_front_card.slot_index or 0))
        end
    end
    for _, alpha_back_card in ipairs(back_line) do
        if alpha_back_card.inventory_item_id ~= nil and alpha_back_card.inventory_item_id ~= "" then
            lib_battle_common.append_client_action(state, "alpha_hand_to_back_line:" .. alpha_back_card.inventory_item_id .. "," .. (alpha_back_card.slot_index or 0))
        end
    end
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

    lib_battle_common.append_client_action(state, "alpha_take_lamp")

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

-- Filters other_cards, returning only totem_pulse cards.
local function filter_totem_pulse_cards(other_cards)
    local totem_pulse_cards = {}
    for _, other_card in ipairs(other_cards) do
        if other_card.item_definition_code_name == "totem_pulse" then
            table.insert(totem_pulse_cards, other_card)
        end
    end
    return totem_pulse_cards
end

-- Goblin Shaman strategy:
--   Front : 1 character, always face-down.
--   Back  : ALL totem_pulse cards face-up (slot permitting).
deploy_goblin_shaman = function(state)
    lib_battle_common.dlog("[card_deploy] == deploy_goblin_shaman ==")

    local omega_front_line = state.omega_front_line or {}
    local omega_back_line  = state.omega_back_line  or {}
    local deployed_ids     = {}
    local front_deployed   = {}
    local back_deployed    = {}

    local hand_cards                   = collect_omega_hand_cards(state.omega_hand)
    local character_cards, other_cards = split_omega_cards_by_type(state.item_defs, hand_cards)
    local totem_pulse_cards            = filter_totem_pulse_cards(other_cards)
    lib_battle_common.dlog("[card_deploy] goblin_shaman: characters=" .. #character_cards .. " totem_pulse=" .. #totem_pulse_cards)

    if #character_cards >= 1 then
        local front_face_up = math.random(0, 1) == 1
        deploy_one_card_to_line(omega_front_line, character_cards[1], front_face_up, deployed_ids, front_deployed)
    end

    for _, totem_card in ipairs(totem_pulse_cards) do
        local back_face_up = math.random(0, 1) == 1
        deploy_one_card_to_line(omega_back_line, totem_card, back_face_up, deployed_ids, back_deployed)
    end

    local new_omega_hand = rebuild_omega_hand(state.omega_hand, deployed_ids)
    append_omega_deploy_actions(state, front_deployed, back_deployed)
    lib_battle_common.dlog("[card_deploy] goblin_shaman: deployed " .. #deployed_ids .. " card(s)")

    return omega_front_line, omega_back_line, new_omega_hand, nil
end

-- ─── Dispatch table ────────────────────────────────────────────────────────────
-- Maps enemy_entity_key → deploy function.
-- Add a new entry here when a new enemy deploy strategy is implemented above.

enemy_deploy_dispatch = {
    goblin_shaman = deploy_goblin_shaman,
}

main()