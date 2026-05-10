-- lib_battle_common
-- Shared helpers used across battle scripts.
-- is_library = true

-- ─── Helpers ─────────────────────────────────────────────────────────────────

-- Returns true if the card's item definition metadata.type matches card_type.
-- Looks up the definition from item_defs using card.item_definition_code_name.
function check_card_type(item_defs, card, card_type)
    lib_battle_common.dlog("== check_card_type ==")
    if card == nil then return false end
    if item_defs == nil then return false end
    local code = card.item_definition_code_name
    if code == nil then return false end
    for _, item_def in ipairs(item_defs) do
        if item_def.item_code == code then
            return item_def.metadata ~= nil and item_def.metadata.type == card_type
        end
    end
    return false
end

-- Removes the first card with matching inventory_item_id from a line array.
-- Returns true if a card was removed, false otherwise.
function remove_card_from_line(line, inventory_item_id)
    lib_battle_common.dlog("== remove_card_from_line ==")
    if line == nil then return false end
    for i, card in ipairs(line) do
        if card.inventory_item_id == inventory_item_id then
            table.remove(line, i)
            return true
        end
    end
    return false
end

-- ─── reset_card_turn_state ──────────────────────────────────────────────────
-- Resets per-turn state for a single card using item_defs to restore final_def.
--   trigger              → false
--   final_def            → base_stats.def from item_defs (0 if not found)
--   total_damage_received → 0
-- No-ops if card has no item_definition_code_name.
function reset_card_turn_state(item_defs, reset_card)
    if reset_card == nil then return end
    if reset_card.item_definition_code_name == nil or reset_card.item_definition_code_name == "" then return end
    local base_def = 0
    if item_defs ~= nil then
        for _, item_def in ipairs(item_defs) do
            if item_def.item_code == reset_card.item_definition_code_name then
                base_def = (item_def.base_stats and item_def.base_stats.def) or 0
                break
            end
        end
    end
    reset_card.trigger               = false
    reset_card.final_def             = base_def
    reset_card.total_damage_received = 0
end

-- ─── append_client_action ───────────────────────────────────────────────────
-- Appends a client action with an auto-incremented index prefix.
-- Format: [index]:[action_name] or [index]:[action_name]:[params]
function append_client_action(state, action)
    local index = #state.client_actions + 1
    table.insert(state.client_actions, index .. ":" .. action)
end

-- ─── reset_turn_cards ───────────────────────────────────────────────────────
-- Resets per-turn state on every card in all four battle lines.
function reset_turn_cards(state)
    lib_battle_common.dlog("== reset_turn_cards done ==")

    local lines = {
        state.alpha_front_line or {},
        state.alpha_back_line  or {},
        state.omega_front_line or {},
        state.omega_back_line  or {},
    }
    for _, line in ipairs(lines) do
        for _, reset_card in ipairs(line) do
            lib_battle_common.reset_card_turn_state(state.item_defs, reset_card)
        end
    end
end

-- ─── is_card_stunned ──────────────────────────────────────────────────────
-- Returns true if the card is currently stunned (stun_count > 0).
function is_card_stunned(card)
    if card == nil then return false end
    return (card.stun_count or 0) > 0
end

-- ─── get_draw_card_count ────────────────────────────────────────────────────
-- Returns the number of cards a player draws at the start of their turn.
function get_draw_card_count()
    lib_battle_common.dlog("== get_draw_card_count ==")
    return 2
end

-- ─── dlog ────────────────────────────────────────────────────────────────────
-- Appends msg to output.debug_log only when ctx.game.status == "development".
-- Safe to call unconditionally; no-ops in production.
function dlog(msg)
    if ctx.game == nil or ctx.game.status ~= "development" then return end
    if output.debug_log == nil then output.debug_log = {} end
    table.insert(output.debug_log, msg)
end

-- ─── hide_unrevealed_omega_cards ─────────────────────────────────────────────
-- Strips sensitive fields from omega cards that are not yet revealed to alpha.
-- Clears item_definition_code_name and final_def for any card where
-- face_up == false or expose == false.
function hide_unrevealed_omega_cards(state)
    local omega_battle_lines = { state.omega_front_line or {}, state.omega_back_line or {} }
    for _, omega_line in ipairs(omega_battle_lines) do
        for _, omega_card in ipairs(omega_line) do
            if omega_card.face_up == false or omega_card.expose == false then
                omega_card.item_definition_code_name = nil
                omega_card.final_def                 = nil
            end
        end
    end
end

-- ─── battle_status helpers ────────────────────────────────────────────────────

local function resolve_battle_session()
    local session_id, id_err = game.battle_session_current_id()
    if id_err ~= nil then return nil, nil, id_err end
    if session_id == nil or session_id == "" then
        return nil, nil, "no active battle session"
    end
    local state, get_err = game.battle_session_get(session_id)
    if get_err ~= nil then return nil, nil, get_err end
    if state == nil then return nil, nil, "battle session not found" end
    return session_id, state, nil
end

local function mask_omega_hand(state, is_development)
    output.omega_hand = state.omega_hand
    if not is_development and state.omega_hand ~= nil then
        for _, omega_hand_slot in ipairs(state.omega_hand) do
            omega_hand_slot.item_definition_code_name = nil
        end
    end
end

local function write_alpha_state_output(state, session_id)
    output.session_id             = session_id
    output.alpha_hp               = state.alpha_hp
    output.alpha_the_source       = state.alpha_the_source
    output.alpha_the_source_count = state.alpha_the_source ~= nil and #state.alpha_the_source or 0
    output.alpha_the_void         = state.alpha_the_void
    output.alpha_the_void_count   = state.alpha_the_void ~= nil and #state.alpha_the_void or 0
    output.alpha_hand             = state.alpha_hand
    output.alpha_front_line       = state.alpha_front_line
    output.alpha_back_line        = state.alpha_back_line
end

local function write_omega_state_output(state)
    output.omega_hp               = state.omega_hp
    output.omega_the_source_count = state.omega_the_source ~= nil and #state.omega_the_source or 0
    output.omega_the_void         = state.omega_the_void
    output.omega_the_void_count   = state.omega_the_void ~= nil and #state.omega_the_void or 0
    output.omega_front_line       = state.omega_front_line
    output.omega_back_line        = state.omega_back_line
end

local function build_card_action_list(state)
    local card_action_list = {}
    if state.item_defs == nil then return card_action_list end
    for _, item_def in ipairs(state.item_defs) do
        if item_def.item_code ~= nil and item_def.metadata ~= nil and item_def.metadata.action ~= nil then
            local action_entry = {}
            action_entry.item_code = item_def.item_code
            card_action_list[#card_action_list + 1] = action_entry
        end
    end
    return card_action_list
end

local function write_battle_meta_output(state)
    output.turn             = state.turn
    output.action           = state.action
    output.status           = state.status
    output.next_move        = state.metadata ~= nil and state.metadata.next_move or nil
    output.battle_difficulty = state.metadata ~= nil and state.metadata.battle_difficulty or nil
    output.omega_planning   = state.omega_planning
    output.alpha_defending  = state.alpha_defending
    output.client_actions   = state.client_actions
end

-- ─── battle_status ───────────────────────────────────────────────────────────
-- Reads the current battle session and writes its full state into output.

function battle_status()
    lib_battle_common.dlog("== battle_status ==")
    local session_id, state, resolve_err = resolve_battle_session()
    if resolve_err ~= nil then output.error = resolve_err ; return end

    local is_development  = ctx.game ~= nil and ctx.game.status == "development"
    output.is_development = is_development
    output.game_status    = ctx.game ~= nil and ctx.game.status or nil

    mask_omega_hand(state, is_development)
    write_alpha_state_output(state, session_id)
    lib_battle_common.hide_unrevealed_omega_cards(state)
    write_omega_state_output(state)
    output.item_defs         = is_development and state.item_defs or nil
    -- output.item_defs_actions = build_card_action_list(state)
    write_battle_meta_output(state)
end
