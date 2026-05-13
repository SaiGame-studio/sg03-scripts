require "lib_battle_common"
require "lib_battle_ai"

-- init_cards
-- Draws opening hands for both alpha and omega.
--   Alpha (5 cards):
--     Cards 1-3 : matched from alpha_preset_metadata by inventory_item_id in alpha_the_source.
--     Cards 4-5 : drawn randomly from alpha_the_source.
--   Omega (N cards):
--     Each choose_card_X in omega_preset_metadata holds an item_definition_code_name.
--     One matching card is picked per slot from omega_the_source.
-- Drawn cards are removed from their respective source pools.
--
-- Endpoint: POST /api/v1/games/{game_id}/scripts/init_cards/run
-- Example payload (session_id is optional; omit to use the current active session):
-- {
--   "session_id": "battle-session-uuid"
-- }

local function main()
    local session_id, sid_err = lib_battle_common.resolve_session_id()
    if sid_err ~= nil then output.error = sid_err ; return end
    lib_battle_common.dlog("[init_cards] session resolved: " .. tostring(session_id))

    local state, load_err = lib_battle_common.load_session(session_id)
    if load_err ~= nil then output.error = load_err ; return end

    local alpha_hand, alpha_err = lib_battle_ai.alpha_draw(state, 5)
    if alpha_err ~= nil then output.error = alpha_err ; return end

    local omega_hand, omega_err = lib_battle_ai.omega_draw(state, 5)
    if omega_err ~= nil then output.error = omega_err ; return end

    state.alpha_hand = alpha_hand
    state.omega_hand = omega_hand

    lib_battle_common.append_client_action(state, "alpha_take_lamp")

    state.action       = (state.action or 0) + 1
    state.updated_at = ctx.timestamp
    if state.metadata == nil then state.metadata = {} end
    state.metadata.next_move = "card_deploy"

    local save_err = game.battle_session_update(session_id, state)
    if save_err ~= nil then output.error = save_err ; return end
    lib_battle_common.dlog("[init_cards] session persisted, next_move = card_deploy")

    lib_battle_common.battle_status()
end

-- ─── Functions ───────────────────────────────────────────────────────────────

main()