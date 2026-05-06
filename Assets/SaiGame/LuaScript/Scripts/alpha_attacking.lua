require "lib_battle_common"

-- alpha_attacking.lua
-- Applies attacker's base_atk as damage onto the defender card in the battle state.
-- Accumulated damage is stored directly on the card object inside the session state.
-- If total_damage_received exceeds the defender's final_def, the card is defeated
-- and moved to the_void of its side.
--
-- Payload schema:
--   session_id                  (string, optional)  battle session UUID; omit to use active session
--   attacker_inventory_item_id  (string)  UUID of the attacking card instance
--   defender_inventory_item_id  (string)  UUID of the defending card instance

-- ---------------------------------------------------------------------------
-- Validation
-- ---------------------------------------------------------------------------
if not payload.attacker_inventory_item_id or payload.attacker_inventory_item_id == "" then
    output.error = "missing attacker_inventory_item_id"
    return
end

if not payload.defender_inventory_item_id or payload.defender_inventory_item_id == "" then
    output.error = "missing defender_inventory_item_id"
    return
end

-- ---------------------------------------------------------------------------
-- Resolve session
-- ---------------------------------------------------------------------------
local session_id
if payload.session_id ~= nil and payload.session_id ~= "" then
    session_id = payload.session_id
else
    local sid, sid_err = game.battle_session_current_id()
    if sid_err ~= nil then output.error = sid_err ; return end
    if sid == nil or sid == "" then output.error = "no active battle session" ; return end
    session_id = sid
end

local state, state_err = game.battle_session_get(session_id)
if state_err ~= nil then output.error = state_err ; return end
if state == nil then output.error = "battle session not found" ; return end

local is_development = ctx.game ~= nil and ctx.game.status == "development"
local debug_log = {}
local function dlog(msg)
    game.log(msg)
    if is_development then
        table.insert(debug_log, msg)
    end
end

-- ---------------------------------------------------------------------------
-- Find attacker/defender card in state lines
-- void_key tracks which side (alpha/omega) the defender belongs to,
-- so we know which the_void to send them to if defeated.
-- ---------------------------------------------------------------------------
local named_lines = {
    { line = state.alpha_front_line or {}, line_key = "alpha_front_line", side_void = "alpha_the_void" },
    { line = state.alpha_back_line  or {}, line_key = "alpha_back_line",  side_void = "alpha_the_void" },
    { line = state.omega_front_line or {}, line_key = "omega_front_line", side_void = "omega_the_void" },
    { line = state.omega_back_line  or {}, line_key = "omega_back_line",  side_void = "omega_the_void" },
}

local attacker_card, defender_card, defender_line_key, defender_side_void
for _, entry in ipairs(named_lines) do
    for _, card in ipairs(entry.line) do
        if card.inventory_item_id == payload.attacker_inventory_item_id then
            attacker_card = card
        end
        if card.inventory_item_id == payload.defender_inventory_item_id then
            defender_card      = card
            defender_line_key  = entry.line_key
            defender_side_void = entry.side_void
        end
    end
end

if attacker_card == nil then
    output.error = "attacker card not found in any battle line"
    return
end

if defender_card == nil then
    output.error = "defender card not found in any battle line"
    return
end

-- ---------------------------------------------------------------------------
-- Fetch item definitions to read base_atk / base_def from base_status
-- ---------------------------------------------------------------------------
local attacker_def, atk_def_err = game.get_item_def_by_id(attacker_card.item_def_id)
if atk_def_err ~= nil then output.error = "attacker def fetch error: " .. atk_def_err ; return end

local defender_def, def_def_err = game.get_item_def_by_id(defender_card.item_def_id)
if def_def_err ~= nil then output.error = "defender def fetch error: " .. def_def_err ; return end

local base_atk  = (attacker_def.base_status and attacker_def.base_status.atk) or 0
local base_def  = (defender_def.base_status and defender_def.base_status.def) or 0
local final_def = base_def  -- buffs will be added here later

-- ---------------------------------------------------------------------------
-- Accumulate damage on the defender card object inside the state
-- ---------------------------------------------------------------------------
local prev_damage = defender_card.total_damage_received or 0
defender_card.total_damage_received = prev_damage + base_atk

local total_damage = defender_card.total_damage_received
local defeated     = total_damage > final_def

attacker_card.card_action = "attacking"
defender_card.card_action = defeated and "sent_to_void" or "damaged"

dlog(
    "alpha_attacking: atk=" .. payload.attacker_inventory_item_id ..
    " base_atk=" .. base_atk ..
    " def=" .. payload.defender_inventory_item_id ..
    " base_def=" .. base_def ..
    " final_def=" .. final_def ..
    " total_dmg_received=" .. total_damage ..
    " defeated=" .. tostring(defeated)
)

-- ---------------------------------------------------------------------------
-- If defeated → remove from its line and move to the correct void
-- ---------------------------------------------------------------------------
if defeated then
    lib_battle_common.remove_card_from_line(state[defender_line_key], payload.defender_inventory_item_id)
    if state[defender_side_void] == nil then state[defender_side_void] = {} end
    table.insert(state[defender_side_void], defender_card)
    dlog("card " .. payload.defender_inventory_item_id .. " defeated and moved to " .. defender_side_void)
end

-- ---------------------------------------------------------------------------
-- Save updated state
-- ---------------------------------------------------------------------------
state.action     = (state.action or 0) + 1
state.updated_at = ctx.timestamp

local save_err = game.battle_session_update(session_id, state)
if save_err ~= nil then output.error = "failed to save battle state: " .. save_err ; return end

-- ---------------------------------------------------------------------------
-- Output: full battle state
-- ---------------------------------------------------------------------------
if is_development then output.debug_log = debug_log end
lib_battle_common.battle_status()