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
    for _, iid in ipairs(payload.hand) do
        if iid ~= "" then payload_ids[iid] = true end
    end
    for _, slot in ipairs(payload.front_line or {}) do
        local iid = slot.inventory_item_id
        if iid ~= nil and iid ~= "" then payload_ids[iid] = true end
    end
    for _, slot in ipairs(payload.back_line  or {}) do
        local iid = slot.inventory_item_id
        if iid ~= nil and iid ~= "" then payload_ids[iid] = true end
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

    for iid, _ in pairs(payload_ids) do
        if not state_ids[iid] then
            output.error = "payload item (" .. iid .. ") does not exist in battle state"
            return
        end
    end
    for iid, _ in pairs(state_ids) do
        if not payload_ids[iid] then
            output.error = "state item (" .. iid .. ") is missing from payload"
            return
        end
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
        local iid = payload.hand[i]
        if iid ~= nil and iid ~= "" then
            local card = hand_index[iid]
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

    -- Omega AI deploy cards
    local o_front, o_back, o_hand, ai_err = lib_battle_ai.deploy_omega_cards(state, "normal")
    if ai_err ~= nil then output.error = ai_err ; return end
    state.omega_front_line = o_front
    state.omega_back_line  = o_back
    state.omega_hand       = o_hand

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
    for i, iid in ipairs(payload.hand) do
        if type(iid) ~= "string" then
            return "hand[" .. i .. "] must be a string"
        end
        if iid ~= "" then
            if seen[iid] then
                return "duplicate inventory_item_id in hand: " .. iid
            end
            seen[iid] = "hand"
        end
    end
    for i, slot in ipairs(payload.front_line or {}) do
        if type(slot) ~= "table" then
            return "front_line[" .. i .. "] must be an object"
        end
        local iid = slot.inventory_item_id
        if type(iid) ~= "string" then
            return "front_line[" .. i .. "].inventory_item_id must be a string"
        end
        if type(slot.slot_index) ~= "number" or slot.slot_index < 0 or slot.slot_index >= SLOT_COUNT then
            return "front_line[" .. i .. "].slot_index must be an integer in [0, " .. (SLOT_COUNT - 1) .. "]"
        end
        if iid ~= "" then
            if seen[iid] then
                return "inventory_item_id " .. iid .. " appears in both hand and front_line"
            end
            seen[iid] = "front_line"
        end
    end
    for i, slot in ipairs(payload.back_line or {}) do
        if type(slot) ~= "table" then
            return "back_line[" .. i .. "] must be an object"
        end
        local iid = slot.inventory_item_id
        if type(iid) ~= "string" then
            return "back_line[" .. i .. "].inventory_item_id must be a string"
        end
        if type(slot.slot_index) ~= "number" or slot.slot_index < 0 or slot.slot_index >= SLOT_COUNT then
            return "back_line[" .. i .. "].slot_index must be an integer in [0, " .. (SLOT_COUNT - 1) .. "]"
        end
        if iid ~= "" then
            if seen[iid] then
                return "inventory_item_id " .. iid .. " appears in " .. seen[iid] .. " and back_line"
            end
            seen[iid] = "back_line"
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
        local iid = slot.inventory_item_id
        if iid ~= nil and iid ~= "" then
            local card = hand_index[iid]
            if card == nil then
                return nil, nil, "front_line[" .. i .. "] card (" .. iid .. ") not found in alpha_hand"
            end
            local face_up = slot.face_up == true
            card.face_up     = face_up
            card.expose      = face_up
            card.card_action = "in_front_line"
            card.slot_index  = slot.slot_index
            front_line[slot.slot_index + 1] = card
        end
    end

    local back_line = {}
    for i = 1, SLOT_COUNT do back_line[i] = {} end
    for i, slot in ipairs(payload.back_line or {}) do
        local iid = slot.inventory_item_id
        if iid ~= nil and iid ~= "" then
            local card = hand_index[iid]
            if card == nil then
                return nil, nil, "back_line[" .. i .. "] card (" .. iid .. ") not found in alpha_hand"
            end
            local face_up = slot.face_up == true
            card.face_up     = face_up
            card.expose      = face_up
            card.card_action = "in_back_line"
            card.slot_index  = slot.slot_index
            back_line[slot.slot_index + 1] = card
        end
    end

    return front_line, back_line, nil
end

main()