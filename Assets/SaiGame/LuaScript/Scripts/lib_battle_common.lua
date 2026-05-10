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

-- ─── reset_turn_cards ───────────────────────────────────────────────────────
-- Resets per-turn state on every card in all four battle lines.
--   trigger              → false
--   final_def            → 0
--   total_damage_received → 0
function reset_turn_cards(state)
    lib_battle_common.dlog("== reset_turn_cards done ==")

    local lines = {
        state.alpha_front_line or {},
        state.alpha_back_line  or {},
        state.omega_front_line or {},
        state.omega_back_line  or {},
    }
    for _, line in ipairs(lines) do
        for _, card in ipairs(line) do
            if card.item_definition_code_name ~= nil and card.item_definition_code_name ~= "" then
                card.trigger               = false
                card.final_def             = 0
                card.total_damage_received = 0
            end
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

-- ─── battle_status ───────────────────────────────────────────────────────────
-- Reads the current battle session and writes its full state into output.

function battle_status()
    lib_battle_common.dlog("== battle_status ==")
    local session_id, id_err = game.battle_session_current_id()
    if id_err ~= nil then
        output.error = id_err; return
    end
    if session_id == nil or session_id == "" then
        output.error = "no active battle session"
        return
    end

    local state, get_err = game.battle_session_get(session_id)
    if get_err ~= nil then
        output.error = get_err; return
    end
    if state == nil then
        output.error = "battle session not found"; return
    end

    local is_development  = ctx.game ~= nil and ctx.game.status == "development"

    output.is_development = is_development
    output.game_status    = ctx.game ~= nil and ctx.game.status or nil

    output.omega_hand     = state.omega_hand
    if not is_development and state.omega_hand ~= nil then
        for _, slot in ipairs(state.omega_hand) do
            slot.item_definition_code_name = nil
        end
    end

    output.session_id             = session_id
    output.alpha_hp               = state.alpha_hp
    output.alpha_the_source       = state.alpha_the_source
    output.alpha_the_source_count = state.alpha_the_source ~= nil and #state.alpha_the_source or 0
    output.alpha_the_void         = state.alpha_the_void
    output.alpha_the_void_count   = state.alpha_the_void ~= nil and #state.alpha_the_void or 0
    output.alpha_hand             = state.alpha_hand
    output.alpha_front_line       = state.alpha_front_line
    output.alpha_back_line        = state.alpha_back_line
    output.omega_hp               = state.omega_hp
    output.omega_the_source_count = state.omega_the_source ~= nil and #state.omega_the_source or 0
    output.omega_the_void         = state.omega_the_void
    output.omega_the_void_count   = state.omega_the_void ~= nil and #state.omega_the_void or 0
    -- Hide item identity for omega cards that are not revealed.
    local omega_battle_lines = { state.omega_front_line or {}, state.omega_back_line or {} }
    for _, omega_line in ipairs(omega_battle_lines) do
        for _, omega_card in ipairs(omega_line) do
            if omega_card.face_up == false or omega_card.expose == false then
                omega_card.item_definition_code_name = nil
            end
        end
    end

    output.omega_front_line       = state.omega_front_line
    output.omega_back_line        = state.omega_back_line
    output.item_defs              = is_development and state.item_defs or nil
    output.turn                   = state.turn
    output.action                 = state.action
    output.status                 = state.status
    output.next_move              = state.metadata ~= nil and state.metadata.next_move or nil
    output.battle_difficulty      = state.metadata ~= nil and state.metadata.battle_difficulty or nil
    output.client_actions         = state.client_actions
end
