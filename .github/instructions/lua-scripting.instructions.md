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
- `ctx`: server context with `player_id`, `game_id`, `studio_id`, `timestamp`, and optional enriched data.
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
