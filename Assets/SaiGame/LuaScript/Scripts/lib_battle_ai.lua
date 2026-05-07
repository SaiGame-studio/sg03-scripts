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
        card.card_action = card_action
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