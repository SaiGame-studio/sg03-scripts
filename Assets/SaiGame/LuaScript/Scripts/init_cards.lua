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

-- ── Inlined helpers (from lib_battle_ai) ────────────────────────────────────
local function gen_id()
    local t = "xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx"
    return string.gsub(t, "[xy]", function(c)
        local v = (c == "x") and math.random(0, 15) or math.random(8, 11)
        return string.format("%x", v)
    end)
end

local function find_and_remove(list, inventory_item_id)
    for i, item in ipairs(list) do
        if item.inventory_item_id == inventory_item_id then
            table.remove(list, i)
            return item
        end
    end
    return nil
end

local function find_and_remove_by_code(list, code)
    for i, item in ipairs(list) do
        if item.item_definition_code_name == code then
            table.remove(list, i)
            return item
        end
    end
    return nil
end

local function alpha_draw_random(state, card_count, start_slot)
    lib_battle_common.dlog("[init_cards] == alpha_draw_random == card_count: " .. tostring(card_count))
    start_slot = start_slot or 0
    local source = state.alpha_the_source
    if source == nil then
        return nil, "alpha_the_source not found in session state"
    end
    math.randomseed(ctx.timestamp)
    local hand = {}
    for _ = 1, card_count do
        if #source == 0 then break end
        local idx = math.random(1, #source)
        table.insert(hand, source[idx])
        table.remove(source, idx)
    end
    for i = #hand + 1, card_count do hand[i] = {} end
    for i, hand_card in ipairs(hand) do
        if hand_card.item_definition_code_name ~= nil and hand_card.item_definition_code_name ~= "" then
            hand_card.slot_index  = start_slot + i - 1
            hand_card.trigger     = false
            hand_card.stun_remain = 0
        end
    end
    for _, hand_card in ipairs(hand) do
        if hand_card.inventory_item_id ~= nil and hand_card.inventory_item_id ~= "" then
            lib_battle_common.append_client_action(state,
                "alpha_source_to_hand:" .. hand_card.inventory_item_id .. "," .. (hand_card.slot_index or 0))
        end
    end
    return hand, nil
end

local function omega_draw_random(state, card_count, start_slot)
    lib_battle_common.dlog("[init_cards] == omega_draw_random == card_count: " .. tostring(card_count))
    start_slot = start_slot or 0
    local source = state.omega_the_source
    if source == nil then
        return nil, "omega_the_source not found in session state"
    end
    math.randomseed(ctx.timestamp)
    local hand = {}
    for _ = 1, card_count do
        if #source == 0 then break end
        local idx                     = math.random(1, #source)
        source[idx].id                = gen_id()
        source[idx].inventory_item_id = gen_id()
        table.insert(hand, source[idx])
        table.remove(source, idx)
    end
    for i = #hand + 1, card_count do hand[i] = {} end
    for i, hand_card in ipairs(hand) do
        if hand_card.item_definition_code_name ~= nil and hand_card.item_definition_code_name ~= "" then
            hand_card.slot_index  = start_slot + i - 1
            hand_card.trigger     = false
            hand_card.stun_remain = 0
        end
    end
    for _, hand_card in ipairs(hand) do
        if hand_card.inventory_item_id ~= nil and hand_card.inventory_item_id ~= "" then
            lib_battle_common.append_client_action(state,
                "omega_source_to_hand:" .. hand_card.inventory_item_id .. "," .. (hand_card.slot_index or 0))
        end
    end
    return hand, nil
end
-- ─────────────────────────────────────────────────────────────────────────────

-- Draws Alpha's opening hand: exactly the 3 preset cards chosen by the player
-- (choose_card_1/2/3 from alpha_preset_metadata). No random fill.
-- Returns: hand, err
local function alpha_choose_cards(state)
    lib_battle_common.dlog("[init_cards] == alpha_choose_cards ==")
    local preset = state.alpha_preset_metadata
    if preset == nil then
        return nil, "alpha_preset_metadata not found in session state"
    end

    local source = state.alpha_the_source
    if source == nil then
        return nil, "alpha_the_source not found in session state"
    end

    local slot_names   = { "choose_card_1", "choose_card_2", "choose_card_3" }
    local preset_uuids = { preset.choose_card_1, preset.choose_card_2, preset.choose_card_3 }
    for i, uid in ipairs(preset_uuids) do
        if uid == nil or uid == "" then
            return nil, "alpha_preset_metadata." .. slot_names[i] .. " is missing"
        end
    end

    local hand = {}
    for i, uid in ipairs(preset_uuids) do
        local card = find_and_remove(source, uid)
        if card == nil then
            return nil, "preset card " .. slot_names[i] .. " (" .. uid .. ") not found in alpha_the_source"
        end
        card.slot_index  = i - 1
        card.trigger     = false
        card.stun_remain = 0
        table.insert(hand, card)
    end

    for _, hand_card in ipairs(hand) do
        lib_battle_common.append_client_action(state,
            "alpha_source_to_hand:" .. hand_card.inventory_item_id .. "," .. (hand_card.slot_index or 0))
    end
    lib_battle_common.dlog("[init_cards] alpha_choose_cards: " .. tostring(#hand) .. " cards")

    return hand, nil
end

-- Draws Omega's opening hand: exactly the preset cards from choose_card_1/2/3
-- in metadata.omega.metadata. No random fill.
-- Returns: hand, err
local function omega_choose_cards(state)
    lib_battle_common.dlog("[init_cards] == omega_choose_cards ==")
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

    local slot_keys = { "choose_card_1", "choose_card_2", "choose_card_3" }
    local slots     = {}
    for _, key in ipairs(slot_keys) do
        local code = preset[key]
        if code ~= nil and code ~= "" then
            table.insert(slots, { key = key, code = code })
        end
    end

    if #slots == 0 then
        return nil, "metadata.omega.metadata has no choose_card slots"
    end

    local hand = {}
    for i, slot in ipairs(slots) do
        local card = find_and_remove_by_code(source, slot.code)
        if card == nil then
            return nil, "omega preset " .. slot.key .. " (" .. slot.code .. ") not found in omega_the_source"
        end
        card.id                = gen_id()
        card.inventory_item_id = gen_id()
        card.slot_index        = i - 1
        card.trigger           = false
        card.stun_remain       = 0
        table.insert(hand, card)
    end

    for _, hand_card in ipairs(hand) do
        lib_battle_common.append_client_action(state,
            "omega_source_to_hand:" .. hand_card.inventory_item_id .. "," .. (hand_card.slot_index or 0))
    end
    lib_battle_common.dlog("[init_cards] omega_choose_cards: " .. tostring(#hand) .. " cards")

    return hand, nil
end

-- Draws alpha's opening hand: 3 preset chosen cards + 2 random from alpha_the_source.
-- Returns err or nil.
local function alpha_init_cards(state)
    local alpha_hand, alpha_err = alpha_choose_cards(state)
    if alpha_err ~= nil then return alpha_err end

    local random_hand, random_err = alpha_draw_random(state, 2, #alpha_hand)
    if random_err ~= nil then return random_err end
    for _, card in ipairs(random_hand) do table.insert(alpha_hand, card) end

    state.alpha_hand = alpha_hand
    return nil
end

-- Draws omega's opening hand: 3 preset chosen cards + 2 random from omega_the_source.
-- Returns err or nil.
local function omega_init_cards(state)
    local omega_hand, omega_err = omega_choose_cards(state)
    if omega_err ~= nil then return omega_err end

    local random_hand, random_err = omega_draw_random(state, 2, #omega_hand)
    if random_err ~= nil then return random_err end
    for _, card in ipairs(random_hand) do table.insert(omega_hand, card) end

    state.omega_hand = omega_hand
    return nil
end

local function main()
    local session_id, sid_err = lib_battle_common.resolve_session_id()
    if sid_err ~= nil then
        output.error = sid_err; return
    end
    lib_battle_common.dlog("[init_cards] session resolved: " .. tostring(session_id))

    local state, load_err = lib_battle_common.load_session(session_id)
    if load_err ~= nil then
        output.error = load_err; return
    end

    local alpha_err = alpha_init_cards(state)
    if alpha_err ~= nil then
        output.error = alpha_err; return
    end

    local omega_err = omega_init_cards(state)
    if omega_err ~= nil then
        output.error = omega_err; return
    end

    lib_battle_common.append_client_action(state, "alpha_take_lamp")

    state.action     = (state.action or 0) + 1
    state.updated_at = ctx.timestamp
    if state.metadata == nil then state.metadata = {} end
    state.metadata.next_move = "alpha_turn"

    local save_err = game.battle_session_update(session_id, state)
    if save_err ~= nil then
        output.error = save_err; return
    end
    lib_battle_common.dlog("[init_cards] session persisted, next_move = alpha_turn")

    lib_battle_common.battle_status()
end

-- ─── Functions ───────────────────────────────────────────────────────────────

main()
