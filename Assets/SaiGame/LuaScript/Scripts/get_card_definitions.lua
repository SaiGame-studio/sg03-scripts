-- get_card_definitions
-- Scans alpha_the_source, alpha_the_void, alpha_back_line, alpha_front_line, alpha_hand
-- in the battle session, collects every unique item_definition_code_name, then fetches
-- full item definitions via game.get_item_defs_by_codes and returns them.
--
-- Endpoint: POST /api/v1/games/{game_id}/scripts/get_card_definitions/run
-- Headers:
--   Authorization: Bearer {access_token}
--   Content-Type: application/json
-- Example request body:
-- {
--   "payload": {
--     "session_id": "battle-session-uuid"
--   }
-- }
-- session_id is optional; omit to use the current active session.

local resolve_session_id    -- forward declaration
local load_session          -- forward declaration
local collect_codes_from    -- forward declaration
local collect_codes         -- forward declaration
local fetch_definitions     -- forward declaration

local function main()
    local session_id, sid_err = resolve_session_id()
    if sid_err ~= nil then output.error = sid_err ; return end

    local state, load_err = load_session(session_id)
    if load_err ~= nil then output.error = load_err ; return end

    local codes = collect_codes(state)

    local defs, fetch_err = fetch_definitions(codes)
    if fetch_err ~= nil then output.error = fetch_err ; return end

    state.item_defs = defs
    local save_err = game.battle_session_update(session_id, state)
    if save_err ~= nil then output.error = "failed to save item_defs to battle state: " .. save_err ; return end

    output.session_id  = session_id
    output.codes       = codes
    output.definitions = defs
    output.total       = #defs
end

-- ─── Functions ───────────────────────────────────────────────────────────────

resolve_session_id = function()
    if payload.session_id ~= nil and payload.session_id ~= "" then
        return payload.session_id, nil
    end
    local sid, err = game.battle_session_current_id()
    if err ~= nil then return nil, err end
    if sid == nil or sid == "" then return nil, "no active battle session found" end
    return sid, nil
end

load_session = function(session_id)
    local state, err = game.battle_session_get(session_id)
    if err ~= nil then return nil, err end
    if state == nil then return nil, "battle session not found" end
    return state, nil
end

-- Appends unique code values from slot_list into codes.
-- key specifies which field on each slot holds the code name.
-- seen tracks which codes have already been added to avoid duplicates.
collect_codes_from = function(seen, codes, slot_list, key)
    if slot_list == nil then return end
    for _, slot in ipairs(slot_list) do
        local code = slot[key]
        if code ~= nil and code ~= "" and not seen[code] then
            seen[code]        = true
            codes[#codes + 1] = code
        end
    end
end

collect_codes = function(state)
    local seen  = {}
    local codes = {}
    collect_codes_from(seen, codes, state.alpha_the_source, "item_definition_code_name")
    collect_codes_from(seen, codes, state.alpha_the_void,   "item_definition_code_name")
    collect_codes_from(seen, codes, state.alpha_back_line,  "item_definition_code_name")
    collect_codes_from(seen, codes, state.alpha_front_line, "item_definition_code_name")
    collect_codes_from(seen, codes, state.alpha_hand,       "item_definition_code_name")
    collect_codes_from(seen, codes, state.omega_the_source, "item_definition_code_name")
    collect_codes_from(seen, codes, state.omega_the_void,   "item_definition_code_name")
    collect_codes_from(seen, codes, state.omega_back_line,  "item_definition_code_name")
    collect_codes_from(seen, codes, state.omega_front_line, "item_definition_code_name")
    collect_codes_from(seen, codes, state.omega_hand,       "item_definition_code_name")
    return codes
end

fetch_definitions = function(codes)
    if #codes == 0 then return {}, nil end
    local defs, err = game.get_item_defs_by_codes(codes)
    if err ~= nil then return nil, err end
    return defs or {}, nil
end

main()