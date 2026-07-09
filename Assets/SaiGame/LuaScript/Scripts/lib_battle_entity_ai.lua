-- lib_battle_entity_ai  (is_library = true)
-- Per-enemy AI dispatcher. Enemy-specific logic is defined in separate library files.

function get_enemy_key(state)
    return state.metadata ~= nil and state.metadata.enemy_entity_key or nil
end

function run_enemy_ai_handler(state, handler_name)
    local enemy_key = get_enemy_key(state)
    if enemy_key == "goblin_shaman" then
        if handler_name == "defend" then
            return enemy_ai_goblin_shaman.defend(state)
        end
        if handler_name == "plan_attack" then
            return enemy_ai_goblin_shaman.plan_attack(state)
        end
        if handler_name == "deploy" then
            return enemy_ai_goblin_shaman.deploy(state)
        end
        return nil, nil, nil, "unknown handler for goblin_shaman: " .. tostring(handler_name)
    end

    if handler_name == "deploy" then
        return nil, nil, nil, "no deploy handler for enemy_entity_key: " .. tostring(enemy_key)
    end
    return "no " .. tostring(handler_name) .. " handler for enemy_entity_key: " .. tostring(enemy_key)
end

function run_defend(state)
    return run_enemy_ai_handler(state, "defend")
end

function run_plan_attack(state)
    return run_enemy_ai_handler(state, "plan_attack")
end

function deploy_enemy(state)
    local enemy_key = get_enemy_key(state)
    lib_battle_common.dlog("[entity_ai] deploy_enemy enemy_key=" .. tostring(enemy_key))

    local o_front, o_back, o_hand, deploy_err = run_enemy_ai_handler(state, "deploy")
    if deploy_err ~= nil then return deploy_err end

    state.omega_front_line = o_front
    state.omega_back_line  = o_back
    state.omega_hand       = o_hand
    return nil
end
