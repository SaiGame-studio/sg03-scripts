# ss-go Lua Script Contract

Package: ss-go-lua-ai-contract-pack v1.0.0
Ticket: P2-T80

This is the contract an AI agent must follow when generating Lua scripts for studio members.

## Runtime

| Rule | Value |
| --- | --- |
| Lua runtime | Lua 5.1 via gopher-lua |
| Execution timeout | 500 ms |
| Call stack depth | 200 frames |
| Script body size | 32 KB |
| Output keys | 64 |
| Log lines | 100 |
| Standard libraries | `base`, `table`, `string`, `math` |

Forbidden or unavailable builtins: `dofile`, `loadfile`, `load`, `loadstring`, `require`, `module`, `getfenv`, `setfenv`, `collectgarbage`, `string.dump`, filesystem, network, `os`, and `io`.

## Script Shape

Script names must match `^[a-z][a-z0-9_]*$`.

Scripts read from `payload` and `ctx`, then write JSON-serializable values to `output`.

```lua
local attack = payload.attack or 0
local defense = payload.defense or 0

output.damage = math.max(0, attack - defense)
game.log("damage=" .. output.damage)
```

## Injected Globals

| Global | Purpose |
| --- | --- |
| `payload` | Request payload converted from JSON to Lua tables. |
| `ctx` | Server execution context with `player_id`, `game_id`, `studio_id`, `timestamp`, plus optional enriched data. |
| `output` | Result table collected by Go and returned in the run response. |
| `game` | Server-authoritative helper API table. |
| `print` | Alias for `game.log`. |

## Error Handling

Every `game.*` call that returns an error must be checked before returned data is used.

```lua
local item, err = game.get_item_def_by_id(payload.item_def_id)
if err ~= nil then
    output.error = err
    return
end

output.item_name = item.name
```

Single-value side-effect helpers return only `err`.

```lua
local err = game.grant_item(payload.item_def_id, 1)
if err ~= nil then
    output.error = err
    return
end
```

## Available `game.*` API

| Function | Return pattern | Notes |
| --- | --- | --- |
| `game.log(msg)` | none | Captures one log line. `print(msg)` is an alias. |
| `game.grant_item(item_def_id, amount)` | `err` | Grants an item definition to the current player. `amount` must be positive. |
| `game.deduct_item(item_def_id, amount)` | `err` | Deducts an item definition from the current player. `amount` must be positive. |
| `game.get_item_def_by_id(id)` | `table, err` | Fetches an item definition by UUID. |
| `game.get_item_def_by_code(code)` | `table, err` | Fetches an item definition by code. |
| `game.get_item_instance_by_id(id)` | `table, err` | Fetches a player inventory item instance by UUID. |
| `game.update_item_private_properties(item_id, version, props)` | `err` | Merges private properties. The `level` key is reserved. |
| `game.get_container_def_by_id(id)` | `table, err` | Fetches an item container definition by UUID. |
| `game.get_container_by_id(id)` | `table, err` | Fetches a player container by UUID. |
| `game.get_gacha_pack_by_id(id)` | `table, err` | Fetches a gacha pack definition by UUID. |
| `game.open_gacha_pack(pack_id [, container_id [, idempotency_key]])` | `table, err` | Opens one gacha pack for the authenticated player. |
| `game.get_quest_def_by_id(id)` | `table, err` | Fetches a quest definition by UUID. |
| `game.get_event_type_by_id(id_or_name)` | `table, err` | Fetches an event type by UUID or name. |
| `game.get_event_type_by_name(name)` | `table, err` | Fetches an event type by name. |
| `game.get_entity_def_by_id(id)` | `table, err` | Fetches an entity definition by UUID. |
| `game.get_entity_def_by_key(key)` | `table, err` | Fetches an entity definition by key. |
| `game.entity_pool_random(pool_key)` | `table, err` | Weighted random entity from a pool. |
| `game.entity_pool_min(pool_key, stat_key [, count])` | `table|list, err` | Lowest stat entity or list. `count` max is 100. |
| `game.entity_pool_max(pool_key, stat_key [, count])` | `table|list, err` | Highest stat entity or list. `count` max is 100. |
| `game.get_entity_pool_def_by_id(id)` | `table, err` | Fetches an entity pool definition by UUID. |
| `game.get_entity_pool_def_by_key(pool_key)` | `table, err` | Fetches an entity pool definition by key. |
| `game.get_preset_def_by_id(id)` | `table, err` | Fetches a preset definition by UUID. |
| `game.get_preset_by_id(id)` | `table, err` | Fetches a preset instance by UUID. |
| `game.get_preset_slots(preset_id)` | `list, err` | Fetches preset slots. |
| `game.get_equipped_in_slot(slot_key)` | `table, err` | Fetches the player's equipped item in a slot. |
| `game.battle_session_create(state)` | `session_id, err` | Creates an active battle session. |
| `game.battle_session_get(session_id)` | `table, err` | Reads battle session state. |
| `game.battle_session_update(session_id, state)` | `err` | Overwrites battle state. |
| `game.battle_session_end(session_id [, end_data])` | `err` | Ends a battle session. |
| `game.battle_session_flee(session_id)` | `err` | Marks a battle session as fled. |
| `game.open_entity_drop_packs(session_id, entity_def_id, pack_ids)` | `list, err` | Opens enemy drop packs. Max 7 pack IDs. |

## Agent Rejection Rules

Reject or rewrite scripts that:

- Call any function not listed above.
- Use `require`, `os`, `io`, filesystem, network, dynamic code loading, or bytecode APIs.
- Depend on wall-clock randomness for security-critical outcomes without a server-provided seed.
- Modify data outside `output` unless using an explicit documented side-effect helper.
- Ignore `err` from `game.*` before reading returned data.
