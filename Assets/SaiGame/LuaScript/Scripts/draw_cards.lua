-- draw_cards
-- Alpha draws 5 cards to open the battle.
--   Cards 1-3 : taken from alpha_preset_metadata (choose_card_1/2/3).
--   Cards 4-5 : drawn randomly from alpha_the_source.
-- All 5 cards are placed into alpha_hand and removed from alpha_the_source.
--
-- Endpoint: POST /api/v1/games/{game_id}/scripts/draw_cards/run
-- Example payload (session_id is optional; omit to use the current active session):
-- {
--   "session_id": "battle-session-uuid"
-- }

local resolve_session_id -- forward declaration
local load_session       -- forward declaration
local find_and_remove    -- forward declaration
local alpha_draw            -- forward declaration

local function main()
    local session_id, sid_err = resolve_session_id()
    if sid_err ~= nil then output.error = sid_err ; return end

    local state, load_err = load_session(session_id)
    if load_err ~= nil then output.error = load_err ; return end

    local hand, draw_err = alpha_draw(state)
    if draw_err ~= nil then output.error = draw_err ; return end

    state.alpha_hand = hand
    state.updated_at = ctx.timestamp

    local save_err = game.battle_session_update(session_id, state)
    if save_err ~= nil then output.error = save_err ; return end

    output.session_id  = session_id
    output.alpha_hand  = hand
    output.cards_drawn = #hand
end

-- ─── Functions ───────────────────────────────────────────────────────────────

-- Returns session_id from payload if provided, otherwise fetches the current active session.
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

-- Finds the first item in list where item.inventory_item_id == iid,
-- removes it from the list, and returns the item. Returns nil if not found.
find_and_remove = function(list, iid)
    for i, item in ipairs(list) do
        if item.inventory_item_id == iid then
            table.remove(list, i)
            return item
        end
    end
    return nil
end

alpha_draw = function(state)
    local preset = state.alpha_preset_metadata
    if preset == nil then
        return nil, "alpha_preset_metadata not found in session state"
    end

    local source = state.alpha_the_source
    if source == nil then
        return nil, "alpha_the_source not found in session state"
    end

    -- choose_card_1/2/3 are plain inventory_item_id UUIDs
    local slot_names = { "choose_card_1", "choose_card_2", "choose_card_3" }
    local preset_uuids = { preset.choose_card_1, preset.choose_card_2, preset.choose_card_3 }
    for i, uid in ipairs(preset_uuids) do
        if uid == nil or uid == "" then
            return nil, "alpha_preset_metadata." .. slot_names[i] .. " is missing"
        end
    end

    -- Find and remove each preset card from alpha_the_source by inventory_item_id
    local preset_cards = {}
    for i, uid in ipairs(preset_uuids) do
        local card = find_and_remove(source, uid)
        if card == nil then
            return nil, "preset card " .. slot_names[i] .. " (" .. uid .. ") not found in alpha_the_source"
        end
        table.insert(preset_cards, card)
    end

    -- Draw 2 more cards at random from the remaining source
    if #source < 2 then
        return nil, "alpha_the_source has fewer than 2 remaining cards after removing preset cards"
    end

    math.randomseed(ctx.timestamp)

    local random_cards = {}
    for _ = 1, 2 do
        local idx = math.random(1, #source)
        table.insert(random_cards, source[idx])
        table.remove(source, idx)
    end

    -- Build alpha_hand: 3 preset cards followed by 2 random cards
    local hand = {}
    for _, card in ipairs(preset_cards) do
        table.insert(hand, card)
    end
    for _, card in ipairs(random_cards) do
        table.insert(hand, card)
    end

    -- state.alpha_the_source has already been mutated in-place above
    return hand, nil
end

main()