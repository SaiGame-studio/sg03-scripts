-- Usage: create or update this file as a backend Lua script, then run it through the script API.
-- Endpoint: POST /api/v1/games/{game_id}/scripts/{script_name}/run
-- Headers:
--   Authorization: Bearer {access_token}
--   Content-Type: application/json
-- Example request body:
-- {
--   "payload": {
--     "session_id": "battle-session-uuid"  (optional, defaults to current active session)
--   }
-- }

local validate_payload   -- forward declaration
local determine_winner -- forward declaration
local end_session      -- forward declaration
local open_drop_packs  -- forward declaration

local function main()
    local err = validate_payload()
    if err ~= nil then output.error = err ; return end

    local session_id, session_err = lib_battle_common.resolve_session_id()
    if session_err ~= nil then output.error = session_err ; return end

    local state, load_err = lib_battle_common.load_session(session_id)
    if load_err ~= nil then output.error = load_err ; return end

    local winner, alpha_hp, omega_hp = determine_winner(state)

    local end_err = end_session(session_id, state, winner)
    if end_err ~= nil then output.error = end_err ; return end

    output.session_id = session_id
    output.status     = "ended"
    output.winner     = winner
    output.turn       = state.turn
    output.alpha_hp   = alpha_hp
    output.omega_hp   = omega_hp

    if winner == "alpha" then
        local drops, drop_err = open_drop_packs(session_id, state)
        if drop_err ~= nil then output.error = drop_err ; return end
        output.drops = drops
    end
end

-- ─── Functions ───────────────────────────────────────────────────────────────

validate_payload = function()
    return nil
end

determine_winner = function(state)
    local alpha_hp = state.alpha_hp or 0
    local omega_hp = state.omega_hp or 0
    local winner
    if alpha_hp > omega_hp then
        winner = "alpha"
    else
        winner = "omega"
    end
    return winner, alpha_hp, omega_hp
end

end_session = function(session_id, state, winner)
    local end_data = {
        winner   = winner,
        reason   = "completed",
        turn     = state.turn or 1,
        ended_at = ctx.timestamp,
    }
    return game.battle_session_end(session_id, end_data)
end

open_drop_packs = function(session_id, state)
    local enemy = state.metadata and state.metadata.omega
    if enemy == nil then return {}, nil end

    local pack_ids = enemy.metadata and enemy.metadata.drop_pack_ids
    if pack_ids == nil or #pack_ids == 0 then return {}, nil end

    local drops, err = game.open_entity_drop_packs(session_id, enemy.id, pack_ids)
    if err ~= nil then return nil, err end
    return drops or {}, nil
end

main()