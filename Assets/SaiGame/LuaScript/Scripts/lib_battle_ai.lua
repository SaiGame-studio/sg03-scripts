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

    for _, hand_card in ipairs(hand) do
        if hand_card.inventory_item_id ~= nil and hand_card.inventory_item_id ~= "" then
            lib_battle_common.append_client_action(state, "alpha_source_to_hand:" .. hand_card.inventory_item_id .. "," .. (hand_card.slot_index or 0))
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

    for _, hand_card in ipairs(hand) do
        if hand_card.inventory_item_id ~= nil and hand_card.inventory_item_id ~= "" then
            lib_battle_common.append_client_action(state, "omega_source_to_hand:" .. hand_card.inventory_item_id .. "," .. (hand_card.slot_index or 0))
        end
    end
    lib_battle_common.dlog("[lib_battle_ai] omega_draw client_actions added: " .. tostring(#hand) .. " cards")

    return hand, nil
end

-- ── deploy_omega_cards ────────────────────────────────────────────────────────
-- Deploys cards from omega_hand into existing omega lines (mid-battle, per turn).
-- Characters → front line (face-down); others → back line (face-down).
-- Returns: front_line, back_line, new_hand, err

-- Places cards from card_list into the first available empty slots of target_line.
-- Returns deployed_ids (by card.id) and deployed_list.
function _fill_line_slots(target_line, card_list, face_up)
    local deployed_ids  = {}
    local deployed_list = {}
    for _, deploy_card in ipairs(card_list) do
        local placed = false
        for slot_i = 1, SLOT_COUNT do
            local existing = target_line[slot_i]
            if existing == nil or existing.item_definition_code_name == nil or existing.item_definition_code_name == "" then
                deploy_card.slot_index = slot_i - 1
                deploy_card.face_up    = face_up
                deploy_card.expose     = face_up
                target_line[slot_i]    = deploy_card
                table.insert(deployed_ids, deploy_card.id)
                table.insert(deployed_list, deploy_card)
                placed = true
                break
            end
        end
        if not placed then
            lib_battle_common.dlog("[lib_battle_ai] _fill_line_slots: no empty slot for card " .. (deploy_card.inventory_item_id or "?"))
        end
    end
    return deployed_ids, deployed_list
end

-- Appends omega_hand_to_front_line / omega_hand_to_back_line client actions.
function _append_mid_deploy_actions(state, front_deployed, back_deployed)
    for _, front_card in ipairs(front_deployed) do
        if front_card.inventory_item_id ~= nil and front_card.inventory_item_id ~= "" then
            lib_battle_common.append_client_action(state, "omega_hand_to_front_line:" .. front_card.inventory_item_id .. "," .. (front_card.slot_index or 0))
        end
    end
    for _, back_card in ipairs(back_deployed) do
        if back_card.inventory_item_id ~= nil and back_card.inventory_item_id ~= "" then
            lib_battle_common.append_client_action(state, "omega_hand_to_back_line:" .. back_card.inventory_item_id .. "," .. (back_card.slot_index or 0))
        end
    end
end

-- Calls reset_card_turn_state on all newly deployed front and back cards.
function _reset_deployed_cards(item_defs, front_deployed, back_deployed)
    for _, front_card in ipairs(front_deployed) do
        lib_battle_common.reset_card_turn_state(item_defs, front_card)
    end
    for _, back_card in ipairs(back_deployed) do
        lib_battle_common.reset_card_turn_state(item_defs, back_card)
    end
end

function deploy_omega_cards(state, difficulty)
    lib_battle_common.dlog("[lib_battle_ai] == deploy_omega_cards == difficulty=" .. tostring(difficulty))
    local omega_front_line = state.omega_front_line or {}
    local omega_back_line  = state.omega_back_line  or {}

    local hand_cards                   = _collect_cards(state.omega_hand or {})
    local character_cards, other_cards = _split_cards_by_type(hand_cards, state.item_defs)

    local front_ids, front_deployed = _fill_line_slots(omega_front_line, character_cards, false)
    local back_ids,  back_deployed  = _fill_line_slots(omega_back_line,  other_cards,     false)

    local all_deployed_ids = {}
    for _, dep_id in ipairs(front_ids) do table.insert(all_deployed_ids, dep_id) end
    for _, dep_id in ipairs(back_ids)  do table.insert(all_deployed_ids, dep_id) end

    local new_hand = _rebuild_hand(state.omega_hand or {}, all_deployed_ids)
    _append_mid_deploy_actions(state, front_deployed, back_deployed)
    _reset_deployed_cards(state.item_defs, front_deployed, back_deployed)

    lib_battle_common.dlog("[lib_battle_ai] deploy_omega_cards: deployed=" .. #all_deployed_ids)
    return omega_front_line, omega_back_line, new_hand, nil
end

-- ── omega_planning_to_attack ──────────────────────────────────────────────────
-- Builds state.omega_planning for the current turn.
-- Each omega front-line card that has not triggered gets one plan entry targeting
-- the first available alpha front-line card (or back-line if front is empty).
-- Returns err or nil.

-- Returns the first real (non-empty-slot) card from line, or nil.
function _find_first_real_card_in_line(line)
    for _, line_card in ipairs(line or {}) do
        if line_card.inventory_item_id ~= nil and line_card.inventory_item_id ~= "" then
            return line_card
        end
    end
    return nil
end

-- Picks the alpha card that omega should attack this turn.
function _pick_alpha_attack_target(state)
    local alpha_front_target = _find_first_real_card_in_line(state.alpha_front_line)
    if alpha_front_target ~= nil then return alpha_front_target end
    return _find_first_real_card_in_line(state.alpha_back_line)
end

function omega_planning_to_attack(state)
    lib_battle_common.dlog("[lib_battle_ai] == omega_planning_to_attack ==")
    state.omega_planning = {}
    local omega_front_line = state.omega_front_line or {}
    for _, attacker_card in ipairs(omega_front_line) do
        local attacker_id = attacker_card.inventory_item_id or ""
        if attacker_id == "" then
            -- empty slot, skip
        elseif attacker_card.trigger == true then
            lib_battle_common.dlog("[lib_battle_ai] omega attacker already triggered: " .. attacker_id)
        else
            local defender_card = _pick_alpha_attack_target(state)
            if defender_card == nil then
                lib_battle_common.dlog("[lib_battle_ai] no alpha target for omega attacker: " .. attacker_id)
            else
                local plan_entry = {}
                plan_entry.action          = "card_attack_card"
                plan_entry.attacker_inv_id = attacker_id
                plan_entry.defender_inv_id = defender_card.inventory_item_id
                table.insert(state.omega_planning, plan_entry)
                lib_battle_common.dlog("[lib_battle_ai] planned: " .. attacker_id .. " -> " .. defender_card.inventory_item_id)
            end
        end
    end
    lib_battle_common.dlog("[lib_battle_ai] omega_planning count=" .. #state.omega_planning)
    return nil
end
