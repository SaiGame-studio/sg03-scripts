include battle_common_lib

-- battle_status
-- Endpoint: POST /api/v1/games/{game_id}/scripts/battle_status/run
-- Headers:
--   Authorization: Bearer {access_token}
--   Content-Type: application/json
-- Example request body:
-- {
--   "payload": {}
-- }
-- No payload fields required. Returns the full state of the player's current battle session.

battle_common_lib.battle_status()
