-- lib_battle_common
-- Shared helpers used across battle scripts.
-- is_library = true

-- ─── Helpers ─────────────────────────────────────────────────────────────────

-- Returns true if the card's item definition metadata.type matches card_type.
-- Looks up the definition from item_defs using card.item_definition_code_name.
function check_card_type(item_defs, card, card_type)
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
    if line == nil then return false end
    for i, card in ipairs(line) do
        if card.inventory_item_id == inventory_item_id then
            table.remove(line, i)
            return true
        end
    end
    return false
end

-- ─── battle_status ───────────────────────────────────────────────────────────
-- Reads the current battle session and writes its full state into output.

function battle_status()
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
    output.alpha_the_void_count   = state.alpha_the_void ~= nil and #state.alpha_the_void or 0
    output.alpha_hand             = state.alpha_hand
    output.alpha_front_line       = state.alpha_front_line
    output.alpha_back_line        = state.alpha_back_line
    output.omega_hp               = state.omega_hp
    output.omega_the_source_count = state.omega_the_source ~= nil and #state.omega_the_source or 0
    output.omega_the_void_count   = state.omega_the_void ~= nil and #state.omega_the_void or 0
    output.omega_front_line       = state.omega_front_line
    output.omega_back_line        = state.omega_back_line
    output.item_defs              = is_development and state.item_defs or nil
    output.turn                   = state.turn
    output.action                 = state.action
    output.status                 = state.status
    output.next_move              = state.metadata ~= nil and state.metadata.next_move or nil
    output.client_actions         = state.client_actions
end
