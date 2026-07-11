require "lib_battle_common"
require "lib_card_ability"
require "ability_all"

-- alpha_card_deploy
-- Finalizes the opening deploy for alpha (player) only.
-- Alpha's card placement is read from the payload; omega deploy is not performed.
--
-- Endpoint: POST /api/v1/games/{game_id}/scripts/alpha_card_deploy/run
-- Example payload (session_id is optional; omit to use the current active session):
-- {
--   "session_id": "battle-session-uuid",
--   "hand":       ["inventory-item-id-6", "", "inventory-item-id-7", "", ""],
--   "front_line": [{"inventory_item_id": "inventory-item-id-1", "face_up": false, "slot_index": 0}, ...],
--   "back_line":  [{"inventory_item_id": "inventory-item-id-3", "face_up": true,  "slot_index": 2}, ...]
-- }
-- face_up=true  → card.face_up=true,  card.expose=true
-- face_up=false → card.face_up=false, card.expose=false
-- slot_index (0-based) determines which position the card occupies in the line.
-- hand is a positional array (array index − 1 = slot); card.slot_index is updated accordingly.
-- Verified by comparing exact inventory_item_id sets: union of payload
-- (hand + front_line + back_line) must match union of state
-- (alpha_hand + alpha_front_line + alpha_back_line) — no item may appear or disappear.

local SLOT_COUNT = lib_battle_common.get_hand_size()

local validate_payload        -- forward declaration
local build_lines             -- forward declaration
local verify_card_sets        -- forward declaration
local check_front_line_limit  -- forward declaration
local build_remaining_hand    -- forward declaration
local append_alpha_deploy_client_actions -- forward declaration

local function max_front_deploy_per_turn()
    return 1
end

local function main()
    local val_err = validate_payload()
    if val_err ~= nil then output.error = val_err ; return end

    local session_id, sid_err = lib_battle_common.resolve_session_id()
    if sid_err ~= nil then output.error = sid_err ; return end

    local state, state_err = lib_battle_common.load_session(session_id)
    if state_err ~= nil then output.error = state_err ; return end
    if state.status == "completed" then output.error = "battle is already completed" ; return end

    if state.metadata == nil or state.metadata.next_move ~= "alpha_turn" then
        output.error = "alpha_card_deploy can only run when next_move is alpha_turn"
        return
    end

    if state.alpha_hand == nil or #state.alpha_hand == 0 then
        output.error = "alpha_hand is empty; run init_cards first"
        return
    end

    local verify_err = verify_card_sets(state)
    if verify_err ~= nil then output.error = verify_err ; return end

    local limit_err = check_front_line_limit(state)
    if limit_err ~= nil then output.error = limit_err ; return end

    local front_line, back_line, build_err = build_lines(state.alpha_hand, state.alpha_front_line, state.alpha_back_line)
    if build_err ~= nil then output.error = build_err ; return end

    -- Capture each card's old location before state is overwritten.
    local old_location = {}
    for _, card in ipairs(state.alpha_hand or {}) do
        if card.inventory_item_id ~= nil and card.inventory_item_id ~= "" then
            old_location[card.inventory_item_id] = "hand"
        end
    end
    for _, card in ipairs(state.alpha_front_line or {}) do
        if card.inventory_item_id ~= nil and card.inventory_item_id ~= "" then
            old_location[card.inventory_item_id] = "front_line"
        end
    end
    for _, card in ipairs(state.alpha_back_line or {}) do
        if card.inventory_item_id ~= nil and card.inventory_item_id ~= "" then
            old_location[card.inventory_item_id] = "back_line"
        end
    end

    state.alpha_hand       = build_remaining_hand(state.alpha_hand)
    state.alpha_front_line = front_line
    state.alpha_back_line  = back_line

    for _, deployed_card in ipairs(front_line) do
        lib_battle_common.reset_card_turn_state(state.item_defs, deployed_card)
    end
    for _, deployed_card in ipairs(back_line) do
        lib_battle_common.reset_card_turn_state(state.item_defs, deployed_card)
    end

    append_alpha_deploy_client_actions(state, old_location)

    state.action     = (state.action or 0) + 1
    state.updated_at = ctx.timestamp

    local save_err = game.battle_session_update(session_id, state)
    if save_err ~= nil then output.error = save_err ; return end

    lib_battle_common.battle_status()
    output.client_actions = state.client_actions
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

-- Resolves each requested card ID against all current alpha card locations and returns two card lists.
-- Returns nil, nil, err on the first ID that is not found in any current location.
build_lines = function(alpha_hand, alpha_front_line, alpha_back_line)
    local hand_index = {}
    for _, card in ipairs(alpha_hand) do
        if card.inventory_item_id ~= nil and card.inventory_item_id ~= "" then
            hand_index[card.inventory_item_id] = card
        end
    end
    for _, card in ipairs(alpha_front_line or {}) do
        if card.inventory_item_id ~= nil and card.inventory_item_id ~= "" then
            hand_index[card.inventory_item_id] = card
        end
    end
    for _, card in ipairs(alpha_back_line or {}) do
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
            card.face_up    = face_up
            card.expose     = face_up
            card.slot_index = slot.slot_index
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
            card.face_up    = face_up
            card.expose     = face_up
            card.slot_index = slot.slot_index
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

-- Appends client actions only for cards that moved from hand to a line.
-- Cards already in front_line or back_line that are repositioned are skipped.
append_alpha_deploy_client_actions = function(state, old_location)
    for _, slot in ipairs(payload.front_line or {}) do
        local id = slot.inventory_item_id
        if id ~= nil and id ~= "" and old_location[id] == "hand" then
            lib_battle_common.append_client_action(state, "alpha_hand_to_front_line:" .. id .. "," .. slot.slot_index)
        end
    end
    for _, slot in ipairs(payload.back_line or {}) do
        local id = slot.inventory_item_id
        if id ~= nil and id ~= "" and old_location[id] == "hand" then
            lib_battle_common.append_client_action(state, "alpha_hand_to_back_line:" .. id .. "," .. slot.slot_index)
        end
    end
end

main()
