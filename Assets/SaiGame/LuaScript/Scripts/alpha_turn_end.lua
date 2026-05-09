require "lib_battle_common"
require "lib_battle_ai"

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
    lib_battle_common.dlog("[alpha_turn_end] session loaded: " .. session_id)

    -- ── Reset per-turn card state (first action) ──────────────────────────
    lib_battle_common.reset_turn_cards(state)

    -- ── Omega draw count ──────────────────────────────────────────────────
    local omega_draw_count = lib_battle_common.get_draw_card_count()
    output.omega_draw_card_count = omega_draw_count

    local omega_new_hand, omega_draw_err = lib_battle_ai.omega_draw(state, omega_draw_count)
    if omega_draw_err ~= nil then output.error = omega_draw_err ; return end
    state.omega_hand = omega_new_hand

    -- ── Omega AI deploy ───────────────────────────────────────────────────
    local ai_difficulty = state.metadata ~= nil and state.metadata.battle_difficulty or "normal"
    local o_front, o_back, o_hand, ai_err = lib_battle_ai.deploy_omega_cards(state, ai_difficulty)
    if ai_err ~= nil then output.error = ai_err ; return end
    state.omega_front_line = o_front
    state.omega_back_line  = o_back
    state.omega_hand       = o_hand

    -- ── Advance turn ──────────────────────────────────────────────────────
    if state.metadata == nil then state.metadata = {} end
    state.metadata.next_move = "omega_turn"
    state.turn = (state.turn or 0) + 1
    lib_battle_common.dlog("[alpha_turn_end] turn advanced to " .. tostring(state.turn) .. ", next_move = omega_turn")

    -- ── Persist ───────────────────────────────────────────────────────────
    local save_err = game.battle_session_update(session_id, state)
    if save_err ~= nil then output.error = save_err ; return end
    lib_battle_common.dlog("[alpha_turn_end] session persisted")

    lib_battle_common.battle_status()
end

main()