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

local SLOT_COUNT = 5 -- number of slots per line (matches card_deploy.lua)

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
        card.slot_index = i - 1
        card.face_up    = face_up
        card.expose     = face_up
        -- card.card_action = card_action
        line[i]         = card
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

-- ── alpha_draw_random ─────────────────────────────────────────────────────────
-- Draws up to card_count (default: get_draw_card_count()) random cards from
-- alpha_the_source into the first available empty slots of state.alpha_hand.
-- Hand always maintains get_hand_size() total slots.
-- Returns err or nil.
function alpha_draw_random(state, card_count)
    card_count      = card_count or lib_battle_common.get_draw_card_count()
    local hand_size = lib_battle_common.get_hand_size()
    lib_battle_common.dlog("[lib_battle_ai] == alpha_draw_random == card_count=" .. tostring(card_count))

    local source = state.alpha_the_source
    if source == nil then
        return "alpha_the_source not found in session state"
    end

    if state.alpha_hand == nil then state.alpha_hand = {} end
    while #state.alpha_hand < hand_size do
        table.insert(state.alpha_hand, {})
    end

    math.randomseed(ctx.timestamp)

    local drawn = 0
    for i = 1, hand_size do
        if drawn >= card_count then break end
        if #source == 0 then break end
        local slot = state.alpha_hand[i]
        if slot == nil or slot.inventory_item_id == nil or slot.inventory_item_id == "" then
            local idx  = math.random(1, #source)
            local card = source[idx]
            table.remove(source, idx)
            card.slot_index  = i - 1
            card.trigger     = false
            card.stun_remain = 0
            state.alpha_hand[i] = card
            lib_battle_common.append_client_action(state,
                "alpha_source_to_hand:" .. card.inventory_item_id .. "," .. tostring(card.slot_index))
            drawn = drawn + 1
        end
    end

    lib_battle_common.dlog("[lib_battle_ai] alpha_draw_random: drawn=" .. tostring(drawn))
    return nil
end

-- ── omega_draw_random ─────────────────────────────────────────────────────────
-- Draws card_count random cards from omega_the_source (no preset logic).
-- start_slot (optional, default 0): slot_index offset for the drawn cards.
-- Returns: hand, err

function omega_draw_random(state, card_count, start_slot)
    lib_battle_common.dlog("[lib_battle_ai] == omega_draw_random == card_count: " .. tostring(card_count))
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
        source[idx].id                = _gen_id()
        source[idx].inventory_item_id = _gen_id()
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
    lib_battle_common.dlog("[lib_battle_ai] omega_draw_random client_actions added: " .. tostring(#hand) .. " cards")

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
            lib_battle_common.dlog("[lib_battle_ai] _fill_line_slots: no empty slot for card " ..
            (deploy_card.inventory_item_id or "?"))
        end
    end
    return deployed_ids, deployed_list
end

-- Appends omega_hand_to_front_line / omega_hand_to_back_line client actions.
function _append_mid_deploy_actions(state, front_deployed, back_deployed)
    for _, front_card in ipairs(front_deployed) do
        if front_card.inventory_item_id ~= nil and front_card.inventory_item_id ~= "" then
            lib_battle_common.append_client_action(state,
                "omega_hand_to_front_line:" .. front_card.inventory_item_id .. "," .. (front_card.slot_index or 0))
        end
    end
    for _, back_card in ipairs(back_deployed) do
        if back_card.inventory_item_id ~= nil and back_card.inventory_item_id ~= "" then
            lib_battle_common.append_client_action(state,
                "omega_hand_to_back_line:" .. back_card.inventory_item_id .. "," .. (back_card.slot_index or 0))
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

function deploy_omega_cards(state)
    lib_battle_common.dlog("[lib_battle_ai] == deploy_omega_cards ==")
    local omega_front_line             = state.omega_front_line or {}
    local omega_back_line              = state.omega_back_line or {}

    local hand_cards                   = _collect_cards(state.omega_hand or {})
    local character_cards, other_cards = _split_cards_by_type(hand_cards, state.item_defs)

    local front_ids, front_deployed    = _fill_line_slots(omega_front_line, character_cards, false)
    local back_ids, back_deployed      = _fill_line_slots(omega_back_line, other_cards, false)

    local all_deployed_ids             = {}
    for _, dep_id in ipairs(front_ids) do table.insert(all_deployed_ids, dep_id) end
    for _, dep_id in ipairs(back_ids) do table.insert(all_deployed_ids, dep_id) end

    local new_hand = _rebuild_hand(state.omega_hand or {}, all_deployed_ids)
    _append_mid_deploy_actions(state, front_deployed, back_deployed)
    _reset_deployed_cards(state.item_defs, front_deployed, back_deployed)

    lib_battle_common.dlog("[lib_battle_ai] deploy_omega_cards: deployed=" .. #all_deployed_ids)
    return omega_front_line, omega_back_line, new_hand, nil
end

-- ── omega_end_turn ───────────────────────────────────────────────────────────
-- Ends omega's attacking turn: clears alpha_defending, sets omega_defending,
-- and advances next_move to "alpha_turn" so the state machine returns control to alpha.
function omega_end_turn(state)
    lib_battle_common.dlog("[lib_battle_ai] == omega_end_turn ==")
    state.alpha_defending = false
    state.turn = (state.turn or 0) + 1
    lib_battle_common.dlog("[lib_battle_ai] omega_end_turn: alpha_defending=false, turn=" ..
    tostring(state.turn))
    lib_battle_common.append_client_action(state, "omega_turn_end:" .. tostring(state.turn))
    alpha_draw_random(state)
    state.metadata.next_move = "alpha_turn"
    lib_battle_common.append_client_action(state, "next_move:alpha_turn")
    state.omega_defending = true
    lib_battle_common.append_client_action(state, "omega_defending")
    lib_battle_common.dlog("[lib_battle_ai] omega_end_turn: next_move=alpha_turn, omega_defending=true")
end

-- ── omega_planning_to_attack ──────────────────────────────────────────────────
-- Builds state.omega_planning for the current turn.
-- Picks ONE untriggered character from omega_front_line to attack the alpha
-- front-line card with the lowest final_def (fallback to alpha back-line).
-- Appends a "omega_plan_attack:attacker_id,defender_id" client action.
-- If no untriggered attacker exists, calls omega_end_turn directly.
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

-- Returns the first untriggered character card in omega_front_line, or nil.
function _find_omega_attacker(state)
    local omega_front_line = state.omega_front_line or {}
    for _, front_card in ipairs(omega_front_line) do
        local attacker_id = front_card.inventory_item_id or ""
        if attacker_id == "" then
            -- empty slot, skip
        elseif front_card.trigger == true then
            lib_battle_common.dlog("[lib_battle_ai] _find_omega_attacker: already triggered: " .. attacker_id)
        else
            local attacker_def = _find_item_def(state.item_defs, front_card.item_definition_code_name)
            local card_type    = attacker_def ~= nil and attacker_def.metadata ~= nil and attacker_def.metadata.type or
            nil
            if card_type == "character" then
                lib_battle_common.dlog("[lib_battle_ai] _find_omega_attacker: selected=" .. attacker_id)
                return front_card
            end
        end
    end
    return nil
end

-- Returns the alpha front-line card with the lowest final_def.
-- Falls back to alpha back-line if front is empty.
function _pick_alpha_attack_target(state)
    local alpha_front_line = state.alpha_front_line or {}
    local lowest_card      = nil
    local lowest_def       = math.huge
    for _, front_card in ipairs(alpha_front_line) do
        if front_card.inventory_item_id ~= nil and front_card.inventory_item_id ~= "" then
            local card_def = front_card.final_def or 0
            lib_battle_common.dlog("[lib_battle_ai] _pick_alpha_attack_target: candidate id=" ..
            front_card.inventory_item_id .. " final_def=" .. card_def)
            if card_def < lowest_def then
                lowest_def  = card_def
                lowest_card = front_card
            end
        end
    end
    if lowest_card ~= nil then
        lib_battle_common.dlog("[lib_battle_ai] _pick_alpha_attack_target: chose front id=" ..
        lowest_card.inventory_item_id .. " def=" .. lowest_def)
        return lowest_card
    end
    local back_card = _find_first_real_card_in_line(state.alpha_back_line)
    if back_card ~= nil then
        lib_battle_common.dlog("[lib_battle_ai] _pick_alpha_attack_target: front empty, chose back id=" ..
        back_card.inventory_item_id)
    end
    return back_card
end

function omega_planning_to_attack(state)
    lib_battle_common.dlog("[lib_battle_ai] == omega_planning_to_attack ==")
    state.omega_planning = {}

    local attacker_card = _find_omega_attacker(state)
    if attacker_card == nil then
        lib_battle_common.dlog(
        "[lib_battle_ai] omega_planning_to_attack: no untriggered character attacker -> calling omega_end_turn")
        omega_end_turn(state)
        return nil
    end

    -- Check if we can attack alpha_hp directly (no character cards on alpha front line)
    local has_alpha_front_character = false
    for _, card in ipairs(state.alpha_front_line or {}) do
        if lib_battle_common.check_card_type(state.item_defs, card, "character") then
            has_alpha_front_character = true
            break
        end
    end

    if not has_alpha_front_character then
        local plan_entry           = {}
        plan_entry.action          = "omega_attack_alpha_hp"
        plan_entry.attacker_inv_id = attacker_card.inventory_item_id
        plan_entry.defender_inv_id = "alpha_hp"
        table.insert(state.omega_planning, plan_entry)

        lib_battle_common.append_client_action(state,
            "omega_planing_character_attack:" .. attacker_card.inventory_item_id .. ",alpha_hp")
        lib_battle_common.dlog("[lib_battle_ai] omega_planning_to_attack: planned direct attack " ..
        attacker_card.inventory_item_id .. " -> alpha_hp")
        return nil
    end

    local defender_card = _pick_alpha_attack_target(state)
    if defender_card == nil then
        lib_battle_common.dlog("[lib_battle_ai] omega_planning_to_attack: no alpha target available")
        return nil
    end

    local plan_entry           = {}
    plan_entry.action          = "card_attack_card"
    plan_entry.attacker_inv_id = attacker_card.inventory_item_id
    plan_entry.defender_inv_id = defender_card.inventory_item_id
    table.insert(state.omega_planning, plan_entry)

    lib_battle_common.append_client_action(state,
        "omega_planing_character_attack:" .. attacker_card.inventory_item_id .. "," .. defender_card.inventory_item_id)
    lib_battle_common.dlog("[lib_battle_ai] omega_planning_to_attack: planned " ..
    attacker_card.inventory_item_id .. " -> " .. defender_card.inventory_item_id)
    return nil
end
