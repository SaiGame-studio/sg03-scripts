require "lib_battle_common"

-- init_cards
-- Draws opening hands for both alpha and omega.
--   Alpha (5 cards):
--     Cards 1-3 : matched from alpha_preset_metadata by inventory_item_id in alpha_the_source.
--     Cards 4-5 : drawn randomly from alpha_the_source.
--   Omega (N cards):
--     Each choose_card_X in omega_preset_metadata holds an item_definition_code_name.
--     One matching card is picked per slot from omega_the_source.
-- Drawn cards are removed from their respective source pools.
--
-- Endpoint: POST /api/v1/games/{game_id}/scripts/init_cards/run
-- Example payload (session_id is optional; omit to use the current active session):
-- {
--   "session_id": "battle-session-uuid"
-- }

local init_card_max = 5

local function gen_id()
    local t = "xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx"
    return string.gsub(t, "[xy]", function(c)
        local v = (c == "x") and math.random(0, 15) or math.random(8, 11)
        return string.format("%x", v)
    end)
end

local resolve_session_id    -- forward declaration
local load_session          -- forward declaration
local find_and_remove       -- forward declaration
local find_and_remove_by_code -- forward declaration
local alpha_draw            -- forward declaration
local omega_draw            -- forward declaration

local function main()
    local session_id, sid_err = resolve_session_id()
    if sid_err ~= nil then output.error = sid_err ; return end

    local state, load_err = load_session(session_id)
    if load_err ~= nil then output.error = load_err ; return end

    local alpha_hand, alpha_err = alpha_draw(state)
    if alpha_err ~= nil then output.error = alpha_err ; return end

    local omega_hand, omega_err = omega_draw(state)
    if omega_err ~= nil then output.error = omega_err ; return end

    state.alpha_hand = alpha_hand
    state.omega_hand = omega_hand

    if state.client_actions == nil then state.client_actions = {} end
    for _, card in ipairs(alpha_hand) do
        if card.inventory_item_id ~= nil and card.inventory_item_id ~= "" then
            table.insert(state.client_actions, "alpha_source_to_hand:" .. card.inventory_item_id .. "," .. (card.slot_index or 0))
        end
    end
    for _, card in ipairs(omega_hand) do
        if card.inventory_item_id ~= nil and card.inventory_item_id ~= "" then
            table.insert(state.client_actions, "omega_source_to_hand:" .. card.inventory_item_id .. "," .. (card.slot_index or 0))
        end
    end

    state.action       = (state.action or 0) + 1
    state.updated_at = ctx.timestamp
    if state.metadata == nil then state.metadata = {} end
    state.metadata.next_move = "card_deploy"

    local save_err = game.battle_session_update(session_id, state)
    if save_err ~= nil then output.error = save_err ; return end

    lib_battle_common.battle_status()
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

-- Finds the first item in list where item.item_definition_code_name == code,
-- removes it from the list, and returns the item. Returns nil if not found.
find_and_remove_by_code = function(list, code)
    for i, item in ipairs(list) do
        if item.item_definition_code_name == code then
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
        -- card.card_action = "draw_from_source_to_hand"
        table.insert(preset_cards, card)
    end

    -- Draw random cards to fill up to init_card_max
    local random_count = init_card_max - #preset_cards
    if #source < random_count then
        return nil, "alpha_the_source has fewer than " .. random_count .. " remaining cards after removing preset cards"
    end

    math.randomseed(ctx.timestamp)

    local random_cards = {}
    for _ = 1, random_count do
        local idx = math.random(1, #source)
        -- source[idx].card_action = "draw_from_source_to_hand"
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

    -- Pad to init_card_max slots with empty slot markers
    for i = #hand + 1, init_card_max do
        hand[i] = {}
    end

    -- Update slot_index to match position in hand (0-based)
    for i, card in ipairs(hand) do
        if card.item_definition_code_name ~= nil and card.item_definition_code_name ~= "" then
            card.slot_index = i - 1
        end
    end

    -- state.alpha_the_source has already been mutated in-place above
    return hand, nil
end

omega_draw = function(state)
    -- omega preset is stored at state.metadata.omega.metadata
    if state.metadata == nil or state.metadata.omega == nil then
        return nil, "metadata.omega not found in session state"
    end
    local preset = state.metadata.omega.metadata
    if preset == nil then
        return nil, "metadata.omega.metadata not found in session state"
    end

    local source = state.omega_the_source
    if source == nil then
        return nil, "omega_the_source not found in session state"
    end

    -- Collect all choose_card_X code names in order; skip missing slots
    local slot_keys  = { "choose_card_1", "choose_card_2", "choose_card_3" }
    local code_names = {}
    for _, key in ipairs(slot_keys) do
        local code = preset[key]
        if code ~= nil and code ~= "" then
            table.insert(code_names, { key = key, code = code })
        end
    end

    if #code_names == 0 then
        return nil, "omega_preset_metadata has no choose_card slots"
    end

    math.randomseed(ctx.timestamp)

    -- Pick one card per slot from omega_the_source by item_definition_code_name
    local hand = {}
    for _, slot in ipairs(code_names) do
        local card = find_and_remove_by_code(source, slot.code)
        if card == nil then
            return nil, "omega preset " .. slot.key .. " (" .. slot.code .. ") not found in omega_the_source"
        end
        card.id                = gen_id()
        card.inventory_item_id = gen_id()
        -- card.card_action = "draw_from_source_to_hand"
        table.insert(hand, card)
    end

    -- Draw random cards to fill up to init_card_max
    local random_count = init_card_max - #hand
    for _ = 1, random_count do
        if #source == 0 then break end
        local idx = math.random(1, #source)
        source[idx].id                = gen_id()
        source[idx].inventory_item_id = gen_id()
        -- source[idx].card_action = "draw_from_source_to_hand"
        table.insert(hand, source[idx])
        table.remove(source, idx)
    end

    -- Pad to init_card_max slots with empty slot markers
    for i = #hand + 1, init_card_max do
        hand[i] = {}
    end

    -- Update slot_index to match position in hand (0-based)
    for i, card in ipairs(hand) do
        if card.item_definition_code_name ~= nil and card.item_definition_code_name ~= "" then
            card.slot_index = i - 1
        end
    end

    -- state.omega_the_source has already been mutated in-place above
    return hand, nil
end

main()