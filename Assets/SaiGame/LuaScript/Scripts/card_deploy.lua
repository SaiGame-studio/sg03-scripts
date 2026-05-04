-- card_deploy
-- Finalizes alpha's opening hand by placing cards into front-line and back-line.
-- Each card ID in the payload must actually exist in state.alpha_hand; duplicates
-- across the two lines are also rejected.
--
-- Endpoint: POST /api/v1/games/{game_id}/scripts/card_deploy/run
-- Example payload (session_id is optional; omit to use the current active session):
-- {
--   "session_id": "battle-session-uuid",
--   "front_line": ["inventory-item-id-1", "inventory-item-id-2"],
--   "back_line":  ["inventory-item-id-3", "inventory-item-id-4", "inventory-item-id-5"]
-- }

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

    local front_line, back_line, build_err = build_lines(state.alpha_hand)
    if build_err ~= nil then output.error = build_err ; return end

    -- Remove placed cards from alpha_hand
    local placed = {}
    for _, iid in ipairs(payload.front_line or {}) do placed[iid] = true end
    for _, iid in ipairs(payload.back_line  or {}) do placed[iid] = true end

    local remaining_hand = {}
    for _, card in ipairs(state.alpha_hand) do
        if not placed[card.inventory_item_id] then
            table.insert(remaining_hand, card)
        end
    end

    state.alpha_hand       = remaining_hand
    state.alpha_front_line = front_line
    state.alpha_back_line  = back_line
    state.action           = (state.action or 0) + 1
    state.updated_at       = ctx.timestamp
    if state.metadata == nil then state.metadata = {} end
    state.metadata.next_move = "alpha_turn"

    local save_err = game.battle_session_update(session_id, state)
    if save_err ~= nil then output.error = save_err ; return end

    output.session_id           = session_id
    output.alpha_front_line     = front_line
    output.alpha_back_line      = back_line
    output.alpha_hand_remaining = #remaining_hand
    output.next_move            = state.metadata.next_move
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
    if payload.front_line ~= nil and type(payload.front_line) ~= "table" then
        return "front_line must be an array of inventory_item_ids"
    end
    if payload.back_line ~= nil and type(payload.back_line) ~= "table" then
        return "back_line must be an array of inventory_item_ids"
    end
    -- Reject duplicates within and across lines
    local seen = {}
    for _, iid in ipairs(payload.front_line or {}) do
        if seen[iid] then
            return "duplicate inventory_item_id in front_line: " .. iid
        end
        seen[iid] = "front_line"
    end
    for _, iid in ipairs(payload.back_line or {}) do
        if seen[iid] then
            return "inventory_item_id " .. iid .. " appears in both lines"
        end
        seen[iid] = "back_line"
    end
    return nil
end

-- Resolves each requested card ID against alpha_hand and returns two card lists.
-- Returns nil, nil, err on the first ID that is not found in the hand.
build_lines = function(alpha_hand)
    -- Index hand by inventory_item_id for O(1) lookup
    local hand_index = {}
    for _, card in ipairs(alpha_hand) do
        hand_index[card.inventory_item_id] = card
    end

    local front_line = {}
    for _, iid in ipairs(payload.front_line or {}) do
        local card = hand_index[iid]
        if card == nil then
            return nil, nil, "front_line card (" .. iid .. ") not found in alpha_hand"
        end
        table.insert(front_line, card)
    end

    local back_line = {}
    for _, iid in ipairs(payload.back_line or {}) do
        local card = hand_index[iid]
        if card == nil then
            return nil, nil, "back_line card (" .. iid .. ") not found in alpha_hand"
        end
        table.insert(back_line, card)
    end

    return front_line, back_line, nil
end

main()