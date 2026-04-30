-- Usage: create or update this file as a backend Lua script, then run it through the script API.
-- Endpoint: POST /api/v1/games/{game_id}/scripts/{script_name}/run
-- Headers:
--   Authorization: Bearer {access_token}
--   Content-Type: application/json
-- Example request body:
-- {
--   "payload": {}
-- }
-- No payload fields required. Returns the full state of the player's current battle session.

local function main()
    local session_id, id_err = game.battle_session_current_id()
    if id_err ~= nil then output.error = id_err ; return end
    if session_id == nil or session_id == "" then
        output.error = "no active battle session"
        return
    end

    local state, get_err = game.battle_session_get(session_id)
    if get_err ~= nil then output.error = get_err ; return end
    if state == nil then output.error = "battle session not found" ; return end

    output.session_id        = session_id
    output.metadata          = state.metadata
    output.alpha_hp          = state.alpha_hp
    output.alpha_the_source  = state.alpha_the_source
    output.alpha_the_void    = state.alpha_the_void
    output.alpha_hand        = state.alpha_hand
    output.alpha_front_line  = state.alpha_front_line
    output.alpha_back_line   = state.alpha_back_line
    output.omega_hp          = state.omega_hp
    output.omega_the_source  = state.omega_the_source
    output.omega_the_void    = state.omega_the_void
    output.omega_hand        = state.omega_hand
    output.omega_front_line  = state.omega_front_line
    output.omega_back_line   = state.omega_back_line
    output.turn              = state.turn
    output.action            = state.action
    output.status            = state.status
end

main()