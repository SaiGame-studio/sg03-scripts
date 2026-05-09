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
    for _, checked_card in ipairs(cards) do
        local item_def  = _find_item_def(item_defs, checked_card.item_definition_code_name)
        local card_type = item_def ~= nil and item_def.metadata ~= nil and item_def.metadata.type or nil
        if card_type == "character" then
            table.insert(characters, checked_card)
        else
            table.insert(others, checked_card)
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
-- Cautious:
--   Front line: deploy 1 character (face random) only if no character is already there.
--   Back line : deploy 1 non-character (face random) into the first empty slot,
--               but only if the back line currently has fewer than 2 cards.

function _deploy_easy(state)
    lib_battle_common.dlog("[lib_battle_ai] == _deploy_easy ==")

    local front_line = state.omega_front_line or {}
    local back_line  = state.omega_back_line  or {}

    -- Count characters already on the front line.
    local front_char_count = 0
    for _, slot_card in ipairs(front_line) do
        if slot_card.item_definition_code_name ~= nil and slot_card.item_definition_code_name ~= "" then
            local slot_item_def  = _find_item_def(state.item_defs, slot_card.item_definition_code_name)
            local slot_card_type = slot_item_def ~= nil and slot_item_def.metadata ~= nil and slot_item_def.metadata.type or nil
            if slot_card_type == "character" then
                front_char_count = front_char_count + 1
            end
        end
    end
    lib_battle_common.dlog("[lib_battle_ai] _deploy_easy: front_char_count = " .. tostring(front_char_count))

    local hand_cards = _collect_cards(state.omega_hand)
    local characters, others = _split_cards_by_type(hand_cards, state.item_defs)
    lib_battle_common.dlog("[lib_battle_ai] _deploy_easy: hand characters = " .. tostring(#characters) .. ", others = " .. tostring(#others))

    math.randomseed(ctx.timestamp)
    local front_face_up = math.random(0, 1) == 1

    local deployed_ids   = {}
    local front_deployed  = {}
    local back_deployed   = {}

    -- Deploy 1 character into the first empty front slot if none on field yet.
    if front_char_count == 0 and #characters >= 1 then
        local deploy_card = characters[1]
        for slot_i = 1, SLOT_COUNT do
            local existing = front_line[slot_i]
            if existing == nil or existing.item_definition_code_name == nil or existing.item_definition_code_name == "" then
                deploy_card.slot_index = slot_i - 1
                deploy_card.face_up    = front_face_up
                deploy_card.expose     = front_face_up
                front_line[slot_i]     = deploy_card
                table.insert(deployed_ids, deploy_card.id)
                table.insert(front_deployed, deploy_card)
                lib_battle_common.dlog("[lib_battle_ai] _deploy_easy: front[" .. slot_i .. "] = " .. tostring(deploy_card.item_definition_code_name) .. ", face_up = " .. tostring(front_face_up))
                break
            end
        end
    end

    -- Add 1 non-character into the first empty back slot, only if back line has fewer than 2 cards.
    local back_card_count = 0
    for _, back_slot in ipairs(back_line) do
        if back_slot.item_definition_code_name ~= nil and back_slot.item_definition_code_name ~= "" then
            back_card_count = back_card_count + 1
        end
    end
    lib_battle_common.dlog("[lib_battle_ai] _deploy_easy: back_card_count = " .. tostring(back_card_count))

    if back_card_count < 2 and #others >= 1 then
        local deploy_card  = others[1]
        local back_face_up = math.random(0, 1) == 1
        for slot_i = 1, SLOT_COUNT do
            local existing = back_line[slot_i]
            if existing == nil or existing.item_definition_code_name == nil or existing.item_definition_code_name == "" then
                deploy_card.slot_index = slot_i - 1
                deploy_card.face_up    = back_face_up
                deploy_card.expose     = back_face_up
                back_line[slot_i]      = deploy_card
                table.insert(deployed_ids, deploy_card.id)
                table.insert(back_deployed, deploy_card)
                lib_battle_common.dlog("[lib_battle_ai] _deploy_easy: back[" .. slot_i .. "] = " .. tostring(deploy_card.item_definition_code_name) .. ", face_up = " .. tostring(back_face_up))
                break
            end
        end
    end

    local hand = _rebuild_hand(state.omega_hand, deployed_ids)
    lib_battle_common.dlog("[lib_battle_ai] _deploy_easy: deployed " .. tostring(#deployed_ids) .. " card(s)")

    if state.client_actions == nil then state.client_actions = {} end
    for _, front_card in ipairs(front_deployed) do
        if front_card.inventory_item_id ~= nil and front_card.inventory_item_id ~= "" then
            table.insert(state.client_actions, "omega_hand_to_front_line:" .. front_card.inventory_item_id .. "," .. (front_card.slot_index or 0))
        end
    end
    for _, back_card in ipairs(back_deployed) do
        if back_card.inventory_item_id ~= nil and back_card.inventory_item_id ~= "" then
            table.insert(state.client_actions, "omega_hand_to_back_line:" .. back_card.inventory_item_id .. "," .. (back_card.slot_index or 0))
        end
    end

    return front_line, back_line, hand, nil
end

-- ── Normal ───────────────────────────────────────────────────────────────────
-- Balanced:
--   Front line: deploy 1 character (face random) if fewer than 2 characters are already there.
--   Back line : deploy up to 2 non-characters (face random) into the first empty slots,
--               but only if the back line currently has fewer than 3 cards.

function _deploy_normal(state)
    lib_battle_common.dlog("[lib_battle_ai] == _deploy_normal ==")

    local front_line = state.omega_front_line or {}
    local back_line  = state.omega_back_line  or {}

    -- Count characters already on the front line.
    local front_char_count = 0
    for _, slot_card in ipairs(front_line) do
        if slot_card.item_definition_code_name ~= nil and slot_card.item_definition_code_name ~= "" then
            local slot_item_def  = _find_item_def(state.item_defs, slot_card.item_definition_code_name)
            local slot_card_type = slot_item_def ~= nil and slot_item_def.metadata ~= nil and slot_item_def.metadata.type or nil
            if slot_card_type == "character" then
                front_char_count = front_char_count + 1
            end
        end
    end
    lib_battle_common.dlog("[lib_battle_ai] _deploy_normal: front_char_count = " .. tostring(front_char_count))

    local hand_cards = _collect_cards(state.omega_hand)
    local characters, others = _split_cards_by_type(hand_cards, state.item_defs)
    lib_battle_common.dlog("[lib_battle_ai] _deploy_normal: hand characters = " .. tostring(#characters) .. ", others = " .. tostring(#others))

    math.randomseed(ctx.timestamp)
    local front_face_up = math.random(0, 1) == 1

    local deployed_ids   = {}
    local front_deployed  = {}
    local back_deployed   = {}

    -- Deploy 1 character into the first empty front slot if fewer than 2 on field.
    if front_char_count < 2 and #characters >= 1 then
        local deploy_card = characters[1]
        for slot_i = 1, SLOT_COUNT do
            local existing = front_line[slot_i]
            if existing == nil or existing.item_definition_code_name == nil or existing.item_definition_code_name == "" then
                deploy_card.slot_index = slot_i - 1
                deploy_card.face_up    = front_face_up
                deploy_card.expose     = front_face_up
                front_line[slot_i]     = deploy_card
                table.insert(deployed_ids, deploy_card.id)
                table.insert(front_deployed, deploy_card)
                lib_battle_common.dlog("[lib_battle_ai] _deploy_normal: front[" .. slot_i .. "] = " .. tostring(deploy_card.item_definition_code_name) .. ", face_up = " .. tostring(front_face_up))
                break
            end
        end
    end

    -- Add up to 2 non-characters into the first empty back slots (face random), only if back line has fewer than 3 cards.
    local back_card_count = 0
    for _, back_slot in ipairs(back_line) do
        if back_slot.item_definition_code_name ~= nil and back_slot.item_definition_code_name ~= "" then
            back_card_count = back_card_count + 1
        end
    end
    lib_battle_common.dlog("[lib_battle_ai] _deploy_normal: back_card_count = " .. tostring(back_card_count))

    if back_card_count < 3 then
        local back_deployed_count = 0
        local other_index         = 1
        while back_deployed_count < 2 and other_index <= #others do
            local deploy_card  = others[other_index]
            local back_face_up = math.random(0, 1) == 1
            for slot_i = 1, SLOT_COUNT do
                local existing = back_line[slot_i]
                if existing == nil or existing.item_definition_code_name == nil or existing.item_definition_code_name == "" then
                    deploy_card.slot_index = slot_i - 1
                    deploy_card.face_up    = back_face_up
                    deploy_card.expose     = back_face_up
                    back_line[slot_i]      = deploy_card
                    table.insert(deployed_ids, deploy_card.id)
                    table.insert(back_deployed, deploy_card)
                    lib_battle_common.dlog("[lib_battle_ai] _deploy_normal: back[" .. slot_i .. "] = " .. tostring(deploy_card.item_definition_code_name) .. ", face_up = " .. tostring(back_face_up))
                    back_deployed_count = back_deployed_count + 1
                    break
                end
            end
            other_index = other_index + 1
        end
    end

    local hand = _rebuild_hand(state.omega_hand, deployed_ids)
    lib_battle_common.dlog("[lib_battle_ai] _deploy_normal: deployed " .. tostring(#deployed_ids) .. " new card(s)")

    if state.client_actions == nil then state.client_actions = {} end
    for _, front_card in ipairs(front_deployed) do
        if front_card.inventory_item_id ~= nil and front_card.inventory_item_id ~= "" then
            table.insert(state.client_actions, "omega_hand_to_front_line:" .. front_card.inventory_item_id .. "," .. (front_card.slot_index or 0))
        end
    end
    for _, back_card in ipairs(back_deployed) do
        if back_card.inventory_item_id ~= nil and back_card.inventory_item_id ~= "" then
            table.insert(state.client_actions, "omega_hand_to_back_line:" .. back_card.inventory_item_id .. "," .. (back_card.slot_index or 0))
        end
    end

    return front_line, back_line, hand, nil
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
    -- max 1 character per deploy
    if #characters >= 1 then table.insert(front_cards, characters[1]) end
    for i = 1, math.min(2, #others) do table.insert(back_cards, others[i]) end

    local deployed_ids = {}
    for _, deploy_card in ipairs(front_cards) do table.insert(deployed_ids, deploy_card.id) end
    for _, deploy_card in ipairs(back_cards)  do table.insert(deployed_ids, deploy_card.id) end

    local front = _build_line(front_cards, false, "in_front_line")
    local back  = _build_line(back_cards,  false, "in_back_line")
    local hand  = _rebuild_hand(state.omega_hand, deployed_ids)
    lib_battle_common.dlog("[lib_battle_ai] _deploy_hard: deployed " .. tostring(#deployed_ids) .. " new card(s)")

    if state.client_actions == nil then state.client_actions = {} end
    for _, front_card in ipairs(front_cards) do
        if front_card.inventory_item_id ~= nil and front_card.inventory_item_id ~= "" then
            table.insert(state.client_actions, "omega_hand_to_front_line:" .. front_card.inventory_item_id .. "," .. (front_card.slot_index or 0))
        end
    end
    for _, back_card in ipairs(back_cards) do
        if back_card.inventory_item_id ~= nil and back_card.inventory_item_id ~= "" then
            table.insert(state.client_actions, "omega_hand_to_back_line:" .. back_card.inventory_item_id .. "," .. (back_card.slot_index or 0))
        end
    end

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
        if #hand >= card_count then break end
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

-- ── omega_try_to_attack ───────────────────────────────────────────────────────
-- Plans Omega's deal_damage_to_character attack:
--   attacker : first non-stunned card in omega_front_line.
--   defender : first character card in alpha_front_line.
-- (attacker-ability attacks that can hit back-line are handled separately.)
-- Appends a client action: "omega_planing:attack,<omega_inv_id>,<alpha_inv_id>"
-- Returns: err

function omega_try_to_attack(state)
    lib_battle_common.dlog("[lib_battle_ai] == omega_try_to_attack ==")
    if type(state) ~= "table" then
        return "omega_try_to_attack: state must be a table"
    end

    -- Pick first valid omega attacker from front line (must not be stunned).
    local omega_attacker = nil
    local omega_front_line = state.omega_front_line or {}
    for _, omega_card in ipairs(omega_front_line) do
        if omega_card.inventory_item_id ~= nil and omega_card.inventory_item_id ~= ""
            and not lib_battle_common.is_card_stunned(omega_card) then
            omega_attacker = omega_card
            break
        end
    end

    if omega_attacker == nil then
        lib_battle_common.dlog("[lib_battle_ai] omega_try_to_attack: no valid omega attacker, skipping")
        return nil
    end

    -- deal_damage_to_character: defender must be a character in alpha_front_line only.
    local alpha_defender = nil
    local alpha_front_line = state.alpha_front_line or {}
    for _, alpha_card in ipairs(alpha_front_line) do
        if alpha_card.inventory_item_id ~= nil and alpha_card.inventory_item_id ~= ""
            and lib_battle_common.check_card_type(state.item_defs, alpha_card, "character") then
            alpha_defender = alpha_card
            break
        end
    end

    if alpha_defender == nil then
        lib_battle_common.dlog("[lib_battle_ai] omega_try_to_attack: no character defender in alpha_front_line, skipping")
        return nil
    end

    if state.client_actions == nil then state.client_actions = {} end
    local attack_action = "omega_planing:attack," .. omega_attacker.inventory_item_id .. "," .. alpha_defender.inventory_item_id
    table.insert(state.client_actions, attack_action)
    lib_battle_common.dlog("[lib_battle_ai] omega_try_to_attack: " .. attack_action)

    return nil
end