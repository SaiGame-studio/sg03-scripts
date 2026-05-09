require "lib_battle_common"
require "lib_battle_ai"

-- card_deploy
-- Finalizes alpha's opening hand by placing cards into front-line and back-line.
-- Each card ID in the payload must actually exist in state.alpha_hand; duplicates
-- across the two lines are also rejected.
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

local resolve_session_id  -- forward declaration
local load_session        -- forward declaration
local validate_payload    -- forward declaration
local build_lines         -- forward declaration

local function main()
    local val_err = validate_payload()
    if val_err ~= nil then output.error = val_err ; return end

    local session_id, sid_err = resolve_session_id()
    if sid_err ~= nil then output.error = sid_err ; return end

    local state, load_err = load_session(session_id)
    if load_err ~= nil then output.error = load_err ; return end

    if state.alpha_hand == nil or #state.alpha_hand == 0 then
        output.error = "alpha_hand is empty; run init_cards first"
        return
    end

    -- Cross-verify by inventory_item_id across all 3 groups on each side.
    -- Payload set : hand + front_line + back_line
    -- State set   : alpha_hand + alpha_front_line + alpha_back_line (card objects)
    local payload_ids = {}
    for _, inventory_item_id in ipairs(payload.hand) do
        if inventory_item_id ~= "" then payload_ids[inventory_item_id] = true end
    end
    for _, slot in ipairs(payload.front_line or {}) do
        local inventory_item_id = slot.inventory_item_id
        if inventory_item_id ~= nil and inventory_item_id ~= "" then payload_ids[inventory_item_id] = true end
    end
    for _, slot in ipairs(payload.back_line  or {}) do
        local inventory_item_id = slot.inventory_item_id
        if inventory_item_id ~= nil and inventory_item_id ~= "" then payload_ids[inventory_item_id] = true end
    end

    local state_ids = {}
    for _, card in ipairs(state.alpha_hand) do
        if card.inventory_item_id ~= nil and card.inventory_item_id ~= "" then
            state_ids[card.inventory_item_id] = true
        end
    end
    for _, card in ipairs(state.alpha_front_line or {}) do
        if card.inventory_item_id ~= nil and card.inventory_item_id ~= "" then
            state_ids[card.inventory_item_id] = true
        end
    end
    for _, card in ipairs(state.alpha_back_line or {}) do
        if card.inventory_item_id ~= nil and card.inventory_item_id ~= "" then
            state_ids[card.inventory_item_id] = true
        end
    end

    for inventory_item_id, _ in pairs(payload_ids) do
        if not state_ids[inventory_item_id] then
            output.error = "payload item (" .. inventory_item_id .. ") does not exist in battle state"
            return
        end
    end
    for inventory_item_id, _ in pairs(state_ids) do
        if not payload_ids[inventory_item_id] then
            output.error = "state item (" .. inventory_item_id .. ") is missing from payload"
            return
        end
    end

    -- Enforce: at most 1 NEW card may be deployed to front_line per turn.
    -- Cards already present in state.alpha_front_line are not counted as new.
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
    if new_front_count > 1 then
        output.error = "only 1 new card may be deployed to front_line per turn (" .. new_front_count .. " new cards received)"
        return
    end

    local front_line, back_line, build_err = build_lines(state.alpha_hand)
    if build_err ~= nil then output.error = build_err ; return end

    -- Build new alpha_hand from payload.hand preserving slot positions.
    -- Missing or empty-string slots become {} (empty slot marker).
    local hand_index = {}
    for _, card in ipairs(state.alpha_hand) do
        if card.inventory_item_id ~= nil and card.inventory_item_id ~= "" then
            hand_index[card.inventory_item_id] = card
        end
    end

    local remaining_hand = {}
    local remaining_count = 0
    for i = 1, SLOT_COUNT do
        local inventory_item_id = payload.hand[i]
        if inventory_item_id ~= nil and inventory_item_id ~= "" then
            local card = hand_index[inventory_item_id]
            card.slot_index = i - 1
            remaining_hand[i] = card
            remaining_count = remaining_count + 1
        else
            remaining_hand[i] = {}
        end
    end

    state.alpha_hand       = remaining_hand
    state.alpha_front_line = front_line
    state.alpha_back_line  = back_line

    -- Omega AI deploy cards — difficulty comes from battle session metadata (default "normal")
    local ai_difficulty = state.metadata ~= nil and state.metadata.battle_difficulty or "normal"
    local o_front, o_back, o_hand, ai_err = lib_battle_ai.deploy_omega_cards(state, ai_difficulty)
    if ai_err ~= nil then output.error = ai_err ; return end
    state.omega_front_line = o_front
    state.omega_back_line  = o_back
    state.omega_hand       = o_hand

    -- Clear totem_pulse for any omega card that is not face-up (hidden cards).
    local omega_lines = { o_front, o_back }
    for _, omega_line in ipairs(omega_lines) do
        for _, omega_card in ipairs(omega_line) do
            if omega_card.face_up == false or omega_card.expose == false then
                omega_card.totem_pulse = nil
            end
        end
    end

    if state.client_actions == nil then state.client_actions = {} end
    for _, card in ipairs(front_line) do
        if card.inventory_item_id ~= nil and card.inventory_item_id ~= "" then
            table.insert(state.client_actions, "alpha_hand_to_front_line:" .. card.inventory_item_id .. "," .. (card.slot_index or 0))
        end
    end
    for _, card in ipairs(back_line) do
        if card.inventory_item_id ~= nil and card.inventory_item_id ~= "" then
            table.insert(state.client_actions, "alpha_hand_to_back_line:" .. card.inventory_item_id .. "," .. (card.slot_index or 0))
        end
    end
    for _, card in ipairs(o_front) do
        if card.inventory_item_id ~= nil and card.inventory_item_id ~= "" then
            table.insert(state.client_actions, "omega_hand_to_front_line:" .. card.inventory_item_id .. "," .. (card.slot_index or 0))
        end
    end
    for _, card in ipairs(o_back) do
        if card.inventory_item_id ~= nil and card.inventory_item_id ~= "" then
            table.insert(state.client_actions, "omega_hand_to_back_line:" .. card.inventory_item_id .. "," .. (card.slot_index or 0))
        end
    end

    state.action           = (state.action or 0) + 1
    state.updated_at       = ctx.timestamp
    if state.metadata == nil then state.metadata = {} end
    state.metadata.next_move = "alpha_turn"

    local save_err = game.battle_session_update(session_id, state)
    if save_err ~= nil then output.error = save_err ; return end

    lib_battle_common.battle_status()
end

-- ─── Functions ───────────────────────────────────────────────────────────────

resolve_session_id = function()
    if payload.session_id ~= nil and payload.session_id ~= "" then
        return payload.session_id, nil
    end
    local sid, err = game.battle_session_current_id()
    if err ~= nil then return nil, err end
    if sid == nil or sid == "" then return nil, "no active battle session found" end
    return sid, nil
end

load_session = function(session_id)
    local state, err = game.battle_session_get(session_id)
    if err ~= nil then return nil, err end
    if state == nil then return nil, "battle session not found" end
    return state, nil
end

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
    -- Validate each item: skip empty-string slots (empty slot), reject non-string values and duplicates
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
    -- Index hand by inventory_item_id for O(1) lookup
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
            -- card.card_action = "in_front_line"
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
            -- card.card_action = "in_back_line"
            card.slot_index  = slot.slot_index
            back_line[slot.slot_index + 1] = card
        end
    end

    return front_line, back_line, nil
end

main()