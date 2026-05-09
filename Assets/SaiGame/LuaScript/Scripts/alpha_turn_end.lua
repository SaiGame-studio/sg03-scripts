require "lib_battle_common"

-- alpha_turn_end.lua
-- End-of-turn cleanup for Alpha's turn.

local function main()
    -- ── Resolve session ───────────────────────────────────────────────────
    local session_id
    if payload.session_id ~= nil and payload.session_id ~= "" then
        session_id = payload.session_id
    else
        local sid, sid_err = game.battle_session_current_id()
        if sid_err ~= nil then output.error = sid_err ; return end
        if sid == nil or sid == "" then output.error = "no active battle session" ; return end
        session_id = sid
    end

    local state, state_err = game.battle_session_get(session_id)
    if state_err ~= nil then output.error = state_err ; return end
    if state == nil then output.error = "battle session not found" ; return end

    -- ── Reset per-turn card state (first action) ──────────────────────────
    lib_battle_common.reset_turn_cards(state)

    -- ── Advance turn ──────────────────────────────────────────────────────
    if state.metadata == nil then state.metadata = {} end
    state.metadata.next_move = "omega_turn"

    -- ── Persist ───────────────────────────────────────────────────────────
    local save_err = game.battle_session_update(session_id, state)
    if save_err ~= nil then output.error = save_err ; return end

    lib_battle_common.battle_status()
end

main()