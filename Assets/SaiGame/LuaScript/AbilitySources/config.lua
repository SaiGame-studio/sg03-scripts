function get_ability_config(ability_key)
    local configs = {
        twin_reaper = { event = "on_attack", target_positions = { "enemy_frontline" } },
        spinning_slash = { event = "on_attack", target_positions = { "enemy_frontline" } },
        cross_guard = { event = "on_attack", target_positions = { "own_frontline" } },
        totem_pulse = { event = "on_attack", target_positions = { "own_frontline" } },
        back_stab = { event = "on_attack", target_positions = { "enemy_frontline" } },
    }
    return configs[ability_key]
end
