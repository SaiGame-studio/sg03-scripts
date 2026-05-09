-- lib_battle_ai  (is_library = true)
-- AI logic for Omega deploying cards into front_line / back_line,
-- similar to card_deploy.lua but runs automatically based on difficulty.
--
-- Usage from a main script:
--   require "lib_battle_ai"
--   local front, back, hand, err = lib_battle_ai.deploy_omega_cards(state, difficulty)
--   if err ~= nil then ... end
--   state.omega_front_line = front
--   state.omega_back_line  = back
--   state.omega_hand       = hand

local SLOT_COUNT = 5  -- number of slots per line (matches card_deploy.lua)

-- ── Helpers ──────────────────────────────────────────────────────────────────

-- Returns real cards from omega_hand, skipping empty slots {}.
function _collect_cards(hand)
    local cards = {}
    for _, slot in ipairs(hand) do
        if slot.item_definition_code_name ~= nil and slot.item_definition_code_name ~= "" then
            table.insert(cards, slot)
        end
    end
    return cards
end

-- Finds an item def in state.item_defs (array) by item_code.
function _find_item_def(item_defs, code)
    if item_defs == nil then return nil end
    for _, def in ipairs(item_defs) do
        if def.item_code == code then return def end
    end
    return nil
end

-- Splits cards into two groups: characters (front-eligible) and others (back only).
-- Game rule: only character-type cards may be placed in the front line.
function _split_cards_by_type(cards, item_defs)
    local characters = {}
    local others     = {}
    for _, card in ipairs(cards) do
        local def   = _find_item_def(item_defs, card.item_definition_code_name)
        local ctype = def ~= nil and def.metadata ~= nil and def.metadata.type or nil
        if ctype == "character" then
            table.insert(characters, card)
        else
            table.insert(others, card)
        end
    end
    return characters, others
end

-- Builds a SLOT_COUNT-slot line from card_list, assigning slot_index / face_up / expose / card_action.
function _build_line(card_list, face_up, card_action)
    local line = {}
    for i = 1, SLOT_COUNT do
        line[i] = {}
    end
    for i, card in ipairs(card_list) do
        if i > SLOT_COUNT then break end
        card.slot_index  = i - 1
        card.face_up     = face_up
        card.expose      = face_up
        -- card.card_action = card_action
        line[i]          = card
    end
    return line
end

-- Rebuilds omega_hand after deploying some cards (removes deployed cards).
function _rebuild_hand(original_hand, deployed_ids)
    local deployed = {}
    for _, id in ipairs(deployed_ids) do
        deployed[id] = true
    end

    local hand = {}
    for i = 1, SLOT_COUNT do
        hand[i] = {}
    end

    local slot = 1
    for _, card in ipairs(original_hand) do
        if slot > SLOT_COUNT then break end
        local id = card.id
        if id ~= nil and id ~= "" and not deployed[id] then
            card.slot_index = slot - 1
            hand[slot]      = card
            slot            = slot + 1
        end
    end

    return hand
end

-- ── Easy ─────────────────────────────────────────────────────────────────────
-- Cautious: 1 character in front, nothing in back.

function _deploy_easy(state)
    lib_battle_common.dlog("[lib_battle_ai] == _deploy_easy ==")
    local cards = _collect_cards(state.omega_hand)
    if #cards == 0 then
        return nil, nil, nil, "omega_hand is empty"
    end

    local characters, others = _split_cards_by_type(cards, state.item_defs)

    local front_cards = {}
    local back_cards  = {}
    -- game rule: max 1 character per deploy
    if #characters >= 1 then table.insert(front_cards, characters[1]) end

    local deployed_ids = {}
    for _, c in ipairs(front_cards) do table.insert(deployed_ids, c.id) end

    local front = _build_line(front_cards, true, "in_front_line")
    local back  = _build_line(back_cards,  true, "in_back_line")
    local hand  = _rebuild_hand(state.omega_hand, deployed_ids)
    return front, back, hand, nil
end

-- ── Normal ───────────────────────────────────────────────────────────────────
-- Balanced: 1 character in front (face-up), up to 1 non-character in back (face-down).

function _deploy_normal(state)
    lib_battle_common.dlog("[lib_battle_ai] == _deploy_normal ==")
    local cards = _collect_cards(state.omega_hand)
    if #cards == 0 then
        return nil, nil, nil, "omega_hand is empty"
    end

    local characters, others = _split_cards_by_type(cards, state.item_defs)

    local front_cards = {}
    local back_cards  = {}
    -- game rule: max 1 character per deploy
    if #characters >= 1 then table.insert(front_cards, characters[1]) end
    if #others >= 1 then table.insert(back_cards, others[1]) end

    local deployed_ids = {}
    for _, c in ipairs(front_cards) do table.insert(deployed_ids, c.id) end
    for _, c in ipairs(back_cards)  do table.insert(deployed_ids, c.id) end

    local front = _build_line(front_cards, true,  "in_front_line")
    local back  = _build_line(back_cards,  false, "in_back_line")
    local hand  = _rebuild_hand(state.omega_hand, deployed_ids)
    return front, back, hand, nil
end

-- ── Hard ─────────────────────────────────────────────────────────────────────
-- Aggressive: 1 character in front (face-down), up to 2 non-characters in back (face-down).

function _deploy_hard(state)
    lib_battle_common.dlog("[lib_battle_ai] == _deploy_hard ==")
    local cards = _collect_cards(state.omega_hand)
    if #cards == 0 then
        return nil, nil, nil, "omega_hand is empty"
    end

    local characters, others = _split_cards_by_type(cards, state.item_defs)

    local front_cards = {}
    local back_cards  = {}
    -- game rule: max 1 character per deploy
    if #characters >= 1 then table.insert(front_cards, characters[1]) end
    for i = 1, math.min(2, #others) do table.insert(back_cards, others[i]) end

    local deployed_ids = {}
    for _, c in ipairs(front_cards) do table.insert(deployed_ids, c.id) end
    for _, c in ipairs(back_cards)  do table.insert(deployed_ids, c.id) end

    local front = _build_line(front_cards, false, "in_front_line")
    local back  = _build_line(back_cards,  false, "in_back_line")
    local hand  = _rebuild_hand(state.omega_hand, deployed_ids)
    return front, back, hand, nil
end

-- ── Main dispatcher ──────────────────────────────────────────────────────────
-- state      : battle session state (must have state.omega_hand)
-- difficulty : "easy" | "normal" | "hard"
-- Returns: omega_front_line, omega_back_line, omega_hand, err

function deploy_omega_cards(state, difficulty)
    lib_battle_common.dlog("[lib_battle_ai] == deploy_omega_cards == difficulty: " .. tostring(difficulty))
    if type(state) ~= "table" then
        return nil, nil, nil, "deploy_omega_cards: state must be a table"
    end
    if type(difficulty) ~= "string" then
        return nil, nil, nil, "deploy_omega_cards: difficulty must be a string"
    end
    if state.omega_hand == nil then
        return nil, nil, nil, "deploy_omega_cards: state.omega_hand is required"
    end

    if difficulty == "easy" then
        return _deploy_easy(state)
    elseif difficulty == "normal" then
        return _deploy_normal(state)
    elseif difficulty == "hard" then
        return _deploy_hard(state)
    else
        return nil, nil, nil, "deploy_omega_cards: unknown difficulty '" .. difficulty .. "' (easy|normal|hard)"
    end
end

-- ── Draw helpers ─────────────────────────────────────────────────────────────

function _gen_id()
    local t = "xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx"
    return string.gsub(t, "[xy]", function(c)
        local v = (c == "x") and math.random(0, 15) or math.random(8, 11)
        return string.format("%x", v)
    end)
end

function _find_and_remove(list, inventory_item_id)
    for i, item in ipairs(list) do
        if item.inventory_item_id == inventory_item_id then
            table.remove(list, i)
            return item
        end
    end
    return nil
end

function _find_and_remove_by_code(list, code)
    for i, item in ipairs(list) do
        if item.item_definition_code_name == code then
            table.remove(list, i)
            return item
        end
    end
    return nil
end

-- ── alpha_draw ────────────────────────────────────────────────────────────────
-- Draws opening hand for Alpha from alpha_the_source.
--   Cards 1-3 : matched by inventory_item_id from alpha_preset_metadata.
--   Cards 4-5 : drawn randomly from the remaining source.
-- Returns: hand, err

function alpha_draw(state, card_count)
    lib_battle_common.dlog("[lib_battle_ai] == alpha_draw == card_count: " .. tostring(card_count))
    local preset = state.alpha_preset_metadata
    if preset == nil then
        return nil, "alpha_preset_metadata not found in session state"
    end

    local source = state.alpha_the_source
    if source == nil then
        return nil, "alpha_the_source not found in session state"
    end

    local slot_names  = { "choose_card_1", "choose_card_2", "choose_card_3" }
    local preset_uuids = { preset.choose_card_1, preset.choose_card_2, preset.choose_card_3 }
    for i, uid in ipairs(preset_uuids) do
        if uid == nil or uid == "" then
            return nil, "alpha_preset_metadata." .. slot_names[i] .. " is missing"
        end
    end

    local preset_cards = {}
    for i, uid in ipairs(preset_uuids) do
        local preset_card = _find_and_remove(source, uid)
        if preset_card == nil then
            return nil, "preset card " .. slot_names[i] .. " (" .. uid .. ") not found in alpha_the_source"
        end
        table.insert(preset_cards, preset_card)
    end

    local random_count = card_count - #preset_cards
    if #source < random_count then
        return nil, "alpha_the_source has fewer than " .. random_count .. " remaining cards after removing preset cards"
    end

    math.randomseed(ctx.timestamp)

    local random_cards = {}
    for _ = 1, random_count do
        local idx = math.random(1, #source)
        table.insert(random_cards, source[idx])
        table.remove(source, idx)
    end

    local hand = {}
    for _, preset_card in ipairs(preset_cards) do table.insert(hand, preset_card) end
    for _, random_card in ipairs(random_cards) do table.insert(hand, random_card) end
    for i = #hand + 1, card_count do hand[i] = {} end

    for i, hand_card in ipairs(hand) do
        if hand_card.item_definition_code_name ~= nil and hand_card.item_definition_code_name ~= "" then
            hand_card.slot_index  = i - 1
            hand_card.trigger     = false
            hand_card.stun_remain = 0
        end
    end

    if state.client_actions == nil then state.client_actions = {} end
    for _, hand_card in ipairs(hand) do
        if hand_card.inventory_item_id ~= nil and hand_card.inventory_item_id ~= "" then
            table.insert(state.client_actions, "alpha_source_to_hand:" .. hand_card.inventory_item_id .. "," .. (hand_card.slot_index or 0))
        end
    end
    lib_battle_common.dlog("[lib_battle_ai] alpha_draw client_actions added: " .. tostring(#hand) .. " cards")

    return hand, nil
end

-- ── omega_draw ────────────────────────────────────────────────────────────────
-- Draws opening hand for Omega from omega_the_source.
--   Preset slots : matched by item_definition_code_name from metadata.omega.metadata.
--   Remaining    : drawn randomly up to SLOT_COUNT.
-- Returns: hand, err

function omega_draw(state, card_count)
    lib_battle_common.dlog("[lib_battle_ai] == omega_draw == card_count: " .. tostring(card_count))
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

    local hand = {}
    for _, slot in ipairs(code_names) do
        local omega_card = _find_and_remove_by_code(source, slot.code)
        if omega_card == nil then
            return nil, "omega preset " .. slot.key .. " (" .. slot.code .. ") not found in omega_the_source"
        end
        omega_card.id                = _gen_id()
        omega_card.inventory_item_id = _gen_id()
        table.insert(hand, omega_card)
    end

    local random_count = card_count - #hand
    for _ = 1, random_count do
        if #source == 0 then break end
        local idx = math.random(1, #source)
        source[idx].id                = _gen_id()
        source[idx].inventory_item_id = _gen_id()
        table.insert(hand, source[idx])
        table.remove(source, idx)
    end

    for i = #hand + 1, card_count do hand[i] = {} end

    for i, hand_card in ipairs(hand) do
        if hand_card.item_definition_code_name ~= nil and hand_card.item_definition_code_name ~= "" then
            hand_card.slot_index  = i - 1
            hand_card.trigger     = false
            hand_card.stun_remain = 0
        end
    end

    if state.client_actions == nil then state.client_actions = {} end
    for _, hand_card in ipairs(hand) do
        if hand_card.inventory_item_id ~= nil and hand_card.inventory_item_id ~= "" then
            table.insert(state.client_actions, "omega_source_to_hand:" .. hand_card.inventory_item_id .. "," .. (hand_card.slot_index or 0))
        end
    end
    lib_battle_common.dlog("[lib_battle_ai] omega_draw client_actions added: " .. tostring(#hand) .. " cards")

    return hand, nil
end