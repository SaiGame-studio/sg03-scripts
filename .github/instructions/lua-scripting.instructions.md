---
applyTo: "**/*.lua"
---

# Lua Script Coding Rules (ss-go Game Platform)

You are helping a studio member write Lua scripts for the **ss-go game platform**.
Scripts run inside a sandboxed **gopher-lua (Lua 5.1)** VM on the server.
Follow all rules below exactly. Do not invent functions, globals, or behaviors not listed here.

Use this package's contract files as the source of truth:
- `CONTRACT.md`
- `AGENT_PROMPT.md`
- `.lua-libs/ss-go-game-api.lua`

## Mandatory Rules

- Use only Lua 5.1 syntax supported by gopher-lua.
- Use only `payload`, `ctx`, `output`, and documented `game.*` functions.
- Check every returned `err` from `game.*` before using returned data.
- Write results into `output`; do not return values from the chunk.
- Do not use filesystem, network, modules, dynamic code loading, or unavailable standard libraries.
- Do not use `dofile`, `loadfile`, `load`, `loadstring`, `require`, `module`, `getfenv`, `setfenv`, `collectgarbage`, or `string.dump`.

## Library Scripts & Include Directives

A script may import shared library scripts using `include` directives at the top of the file:

```lua
include math_utils
include combat_helpers

output.damage = math_utils.clamp(payload.attack - payload.defense, 0, 999)
```

- Each library is injected as a sandboxed global table; access its functions as `libname.func(args)`.
- Library names must match `^[a-z][a-z0-9_]*$`. Maximum **7** active libraries per game.
- **Inside a library script** (`is_library = true`): only define functions. No top-level executable statements, no `include` directives.

```lua
-- Example library body (is_library = true)
function clamp(v, lo, hi)
    if v < lo then return lo end
    if v > hi then return hi end
    return v
end
```

## Runtime Limits

| Constraint | Value |
| --- | --- |
| Runtime | Lua 5.1 (gopher-lua) |
| Max execution time | 500 ms |
| Max call-stack depth | 200 frames |
| Max script body size | 32 KB |
| Max `output` keys | 64 |
| Max `game.log` lines | 100 |

## Injected Globals

- `payload`: request JSON converted to a Lua table.
- `ctx`: server context with `player_id`, `game_id`, `studio_id`, `timestamp`, `script_version`, and optional enriched data.
  - `ctx.script_version` (integer): version of the currently executing script. Use to guard version-specific logic or expose it in `output` for debugging.
- `output`: result table collected by Go and returned to the caller.
- `game`: server helper API table.
- `print`: alias for `game.log`.

## Error Handling Pattern

```lua
local result, err = game.get_item_def_by_id(payload.item_def_id)
if err ~= nil then
    output.error = err
    return
end

output.item_name = result.name
```

```lua
local err = game.grant_item(payload.item_def_id, 1)
if err ~= nil then
    output.error = err
    return
end
```

## Available API

See `CONTRACT.md` and `.lua-libs/ss-go-game-api.lua` in this package. Do not call any unlisted function.

## lib_battle_common

Before creating any `local function` inside a battle script, always check `lib_battle_common.lua` first to see if that function or a similar one already exists. If it does, use `lib_battle_common.<func>()` instead of redefining it locally.

## Library Import

Always use `require "lib_name"` to import libraries. Never use `include`.

## Language

Always use English in all code, comments, variable names, string literals, and log messages. Never use any other language.

## Variable Naming — No Generic Names

Variable names must describe the **role or domain** of the value, not its type or position.

**Forbidden generic names** (and their required replacements):

| Forbidden | Use instead (example) |
| --- | --- |
| `card` | `attacker_card`, `defender_card`, `target_card` |
| `def` | `attacker_def`, `defender_def`, `target_def`, `item_def` |
| `data` | `event_data`, `payload_data`, `session_data` |
| `obj` | `card_obj`, `session_obj` — or eliminate and use a descriptive name |
| `result` | `battle_result`, `ability_result`, `query_result` |
| `item` | `card_item`, `reward_item`, `loot_item` |
| `val` | `damage_val`, `def_val` — or rename to the concept: `damage`, `armor` |
| `tmp` / `temp` | use the actual concept being stored |
| `k` / `v` (in generic loops) | `key` / `card`, `key` / `ability_key`, etc. |
| `c` (loop variable over cards) | `card`, `attacker_card`, `slot_card`, etc. |
| `t` | the actual type name: `line`, `actions`, `keys` |
| `s` | `state`, `session`, `source` |
| `e` | `err`, `event`, `entry` |

**Rules:**
- When a function receives a card that can be distinguished by role (attacker vs. defender vs. target), always use the role-prefixed name.
- When a variable is a definition/stat block looked up for a specific entity, suffix with `_def` plus a role prefix: `attacker_def`, `target_def`.
- Loop variables must name what they iterate over: `for _, ability_key in ipairs(keys)` not `for _, k`.
- Single-letter variables are forbidden except for math-only locals (`i`, `j`, `n` in numeric for loops).

## Function Call Style — No Inline Table Literals

Never construct a table literal `{ ... }` directly inside a function call argument list.
Always assign the table to a named local variable first, then pass that variable.

**Forbidden:**
```lua
lib_card_ability.trigger_card_ability(state, card, "on_attack", {
    defender_card = defender_card,
    damage_dealt  = damage_dealt,
})
```

**Required:**
```lua
local atk_event_data = {}
atk_event_data.defender_card = defender_card
atk_event_data.damage_dealt  = damage_dealt
lib_card_ability.trigger_card_ability(state, card, "on_attack", atk_event_data)
```

This rule applies to all function calls, including `game.*`, library calls, and local functions.
