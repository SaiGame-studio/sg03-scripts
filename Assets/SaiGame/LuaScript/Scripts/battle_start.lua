-- Usage: create or update this file as a backend Lua script, then run it through the script API.
-- Endpoint: POST /api/v1/games/{game_id}/scripts/{script_name}/run
-- Headers:
--   Authorization: Bearer {access_token}
--   Content-Type: application/json
-- Example request body:
-- {
--   "payload": {
--     "battle_mode": "fast" | "normal" | "long",
--     "battle_difficulty": "easy" | "normal" | "hard",  -- optional, defaults to "normal"
--     "enemy_entity_key": "enemy_key",
--     "preset_instance_id": "preset-uuid"
--   }
-- }

require "lib_battle_common"

-- Deck size limits — shared with player deck validation
local DECK_CARD_MIN = 25
local DECK_CARD_MAX = 52

local function gen_id()
    local t = "xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx"
    return string.gsub(t, "[xy]", function(c)
        local v = (c == "x") and math.random(0, 15) or math.random(8, 11)
        return string.format("%x", v)
    end)
end

local check_enemy            -- forward declaration
local verify_player_preset   -- forward declaration
local validate_payload       -- forward declaration
local resolve_enemy          -- forward declaration
local resolve_mode           -- forward declaration
local build_state            -- forward declaration
local load_player_the_source -- forward declaration
local load_enemy_the_source  -- forward declaration
local load_item_defs         -- forward declaration

local function main()
    local err = validate_payload()
    if err ~= nil then output.error = err ; return end
    lib_battle_common.dlog("[battle_start] payload validated")

    local existing_id = game.battle_session_current_id()
    if existing_id ~= nil and existing_id ~= "" then
        output.error      = "player already has an active battle session"
        output.session_id = existing_id
        return
    end

    local enemy, fetch_err = resolve_enemy()
    if fetch_err ~= nil then output.error = fetch_err ; return end
    lib_battle_common.dlog("[battle_start] enemy resolved: " .. tostring(payload.enemy_entity_key))

    local check_err = check_enemy(enemy)
    if check_err ~= nil then output.error = check_err ; return end
    lib_battle_common.dlog("[battle_start] enemy deck check passed")

    local preset, preset_err = verify_player_preset(payload.preset_instance_id)
    if preset_err ~= nil then output.error = preset_err ; return end
    lib_battle_common.dlog("[battle_start] player preset verified")

    local player_the_source, player_src_err = load_player_the_source(payload.preset_instance_id)
    if player_src_err ~= nil then output.error = player_src_err ; return end
    lib_battle_common.dlog("[battle_start] player source loaded: " .. tostring(#player_the_source) .. " cards")

    local enemy_the_source = load_enemy_the_source(enemy)
    lib_battle_common.dlog("[battle_start] enemy source loaded: " .. tostring(#enemy_the_source) .. " cards")

    local selected_mode = resolve_mode(enemy)
    lib_battle_common.dlog("[battle_start] battle mode: " .. tostring(selected_mode))

    local state = build_state(enemy, selected_mode, player_the_source, enemy_the_source, preset)
    lib_battle_common.append_client_action(state, "alpha_source_spawn_card:" .. #player_the_source)
    lib_battle_common.append_client_action(state, "omega_source_spawn_card:" .. #enemy_the_source)

    local item_defs, defs_err = load_item_defs(player_the_source, enemy_the_source)
    if defs_err ~= nil then output.error = defs_err ; return end
    state.item_defs = item_defs
    lib_battle_common.dlog("[battle_start] item_defs loaded: " .. tostring(#item_defs) .. " definitions")

    local session_id, create_err = game.battle_session_create(state)
    if create_err ~= nil then output.error = create_err ; return end
    lib_battle_common.dlog("[battle_start] session created: " .. tostring(session_id))

    lib_battle_common.battle_status()
end

-- ─── Functions ───────────────────────────────────────────────────────────────

validate_payload = function()
    if payload.battle_mode == nil or payload.battle_mode == "" then
        return "battle_mode is required (fast, normal, long)"
    end
    if payload.battle_mode ~= "fast" and payload.battle_mode ~= "normal" and payload.battle_mode ~= "long" then
        return "battle_mode must be one of: fast, normal, long"
    end
    if payload.enemy_entity_key == nil or payload.enemy_entity_key == "" then
        return "enemy_entity_key is required"
    end
    if payload.preset_instance_id == nil or payload.preset_instance_id == "" then
        return "preset_instance_id is required"
    end
    return nil
end

resolve_enemy = function()
    local enemy, err = game.get_entity_def_by_key(payload.enemy_entity_key)
    if err ~= nil then return nil, err end
    if enemy == nil then return nil, "enemy not found" end
    return enemy, nil
end

resolve_mode = function(enemy)
    local selected = payload.battle_mode
    if enemy.metadata ~= nil and enemy.metadata.battle_modes ~= nil then
        local supported = false
        for _, m in ipairs(enemy.metadata.battle_modes) do
            if m == selected then supported = true ; break end
        end
        if not supported then selected = "normal" end
    end
    return selected
end

build_state = function(enemy, selected_mode, player_the_source, enemy_the_source, preset)
    local hp_map = { fast = 4000, normal = 7000, long = 16000 }
    local hp = hp_map[selected_mode]
    return {
        metadata = {
            alpha_id           = ctx.player_id,
            preset_instance_id = payload.preset_instance_id,
            omega              = enemy,
            enemy_entity_key   = payload.enemy_entity_key,
            battle_mode        = selected_mode,
            started_at         = ctx.timestamp,
            next_move          = "init_cards",
        },
        alpha_preset_metadata  = preset ~= nil and preset.metadata or nil,
        alpha_hp           = hp,
        alpha_the_source   = player_the_source,
        alpha_the_void     = {},
        alpha_hand         = { {}, {}, {}, {}, {} },  -- 5 slots
        alpha_front_line   = { {}, {}, {}, {}, {} },  -- 5 slots
        alpha_back_line    = { {}, {}, {}, {}, {} },  -- 5 slots
        omega_hp           = hp,
        omega_the_source   = enemy_the_source,
        omega_the_void     = {},
        omega_hand         = { {}, {}, {}, {}, {} },  -- 5 slots
        omega_front_line   = { {}, {}, {}, {}, {} },  -- 5 slots
        omega_back_line    = { {}, {}, {}, {}, {} },  -- 5 slots
        turn               = 0,  -- increments when alpha or omega runs out of actions
        action             = 0,  -- each action is one card played
        status             = "active",
        alpha_defending    = false,
        omega_defending    = false,
        client_actions     = {},
        omega_planning     = {},
    }
end

load_player_the_source = function(preset_instance_id)
    local slots, err = game.get_preset_slots(preset_instance_id)
    if err ~= nil then return nil, err end
    for _, slot in ipairs(slots) do
        slot.container_id = nil
        slot.created_at   = nil
    end
    return slots, nil
end

load_enemy_the_source = function(enemy)
    local source = {}
    local slot_index = 0
    if enemy.abilities ~= nil then
        for _, ability in ipairs(enemy.abilities) do
            local count = ability.card_count or 0
            for _ = 1, count do
                source[#source + 1] = {
                    id                        = gen_id(),
                    slot_index                = slot_index,
                    item_definition_code_name = ability.id,
                }
                slot_index = slot_index + 1
            end
        end
    end
    return source
end

verify_player_preset = function(preset_instance_id)
    local preset, err = game.get_preset_by_id(preset_instance_id)
    if err ~= nil then return nil, err end
    if preset == nil then return nil, "preset not found" end

    local slots, slots_err = game.get_preset_slots(preset_instance_id)
    if slots_err ~= nil then return nil, slots_err end

    local total = slots ~= nil and #slots or 0
    if total <= DECK_CARD_MIN then
        return nil, "player deck must have more than " .. DECK_CARD_MIN .. " cards (has " .. total .. ")"
    end
    if total >= DECK_CARD_MAX then
        return nil, "player deck must have fewer than " .. DECK_CARD_MAX .. " cards (has " .. total .. ")"
    end
    return preset, nil
end

check_enemy = function(e)
    if e == nil then return "enemy not found" end
    local total = 0
    if e.abilities ~= nil then
        for _, ability in ipairs(e.abilities) do
            total = total + (ability.card_count or 0)
        end
    end
    if total <= DECK_CARD_MIN then
        return "enemy deck must have more than " .. DECK_CARD_MIN .. " cards (has " .. total .. ")"
    end
    if total >= DECK_CARD_MAX then
        return "enemy deck must have fewer than " .. DECK_CARD_MAX .. " cards (has " .. total .. ")"
    end
    return nil
end

load_item_defs = function(player_source, enemy_source)
    local seen       = {}
    local codes      = {}
    local all_sources = { player_source or {}, enemy_source or {} }
    for _, source_list in ipairs(all_sources) do
        for _, source_card in ipairs(source_list) do
            local code = source_card.item_definition_code_name
            if code ~= nil and code ~= "" and not seen[code] then
                seen[code]        = true
                codes[#codes + 1] = code
            end
        end
    end
    if #codes == 0 then return {}, nil end
    local defs, fetch_err = game.get_item_defs_by_codes(codes)
    if fetch_err ~= nil then return nil, fetch_err end
    return defs or {}, nil
end

main()