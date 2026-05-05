-- lib_battle_ai  (is_library = true)
-- AI logic cho việc Omega deploy card vào front_line / back_line,
-- tương tự card_deploy.lua nhưng chạy tự động theo độ khó.
--
-- Gọi từ script chính:
--   include lib_battle_ai
--   local front, back, hand, err = lib_battle_ai.deploy_omega_cards(state, difficulty)
--   if err ~= nil then ... end
--   state.omega_front_line = front
--   state.omega_back_line  = back
--   state.omega_hand       = hand

local SLOT_COUNT = 5  -- số slot mỗi line (khớp với card_deploy.lua)

-- ── Helpers ──────────────────────────────────────────────────────────────────

-- Lấy danh sách card có thật từ omega_hand (bỏ qua slot rỗng {})
function _collect_cards(hand)
    local cards = {}
    for _, slot in ipairs(hand) do
        if slot.item_definition_code_name ~= nil and slot.item_definition_code_name ~= "" then
            table.insert(cards, slot)
        end
    end
    return cards
end

-- Tạo line 5-slot từ danh sách card, gán slot_index / face_up / expose / card_action
function _build_line(card_list, face_up, card_action)
    local line = {}
    for i = 1, SLOT_COUNT do
        line[i] = {}
    end
    for i, card in ipairs(card_list) do
        if i > SLOT_COUNT then break end
        card.slot_index  = i - 1
        card.face_up     = face_up
        card.expose      = face_up
        card.card_action = card_action
        line[i]          = card
    end
    return line
end

-- Xây lại omega_hand sau khi đã deploy một số card (xóa card đã deploy)
function _rebuild_hand(original_hand, deployed_ids)
    local deployed = {}
    for _, id in ipairs(deployed_ids) do
        deployed[id] = true
    end

    local hand = {}
    for i = 1, SLOT_COUNT do
        hand[i] = {}
    end

    local slot = 1
    for _, card in ipairs(original_hand) do
        if slot > SLOT_COUNT then break end
        local id = card.id
        if id ~= nil and id ~= "" and not deployed[id] then
            card.slot_index = slot - 1
            hand[slot]      = card
            slot            = slot + 1
        end
    end

    return hand
end

-- ── Easy ─────────────────────────────────────────────────────────────────────
-- AI thận trọng: chỉ deploy 1 card face-down vào front, không đặt gì ở back.

function _deploy_easy(state)
    local cards = _collect_cards(state.omega_hand)
    if #cards == 0 then
        return nil, nil, nil, "omega_hand is empty"
    end

    local front_cards = { cards[1] }  -- 1 card ở front
    local back_cards  = {}            -- back trống

    local deployed_ids = {}
    for _, c in ipairs(front_cards) do table.insert(deployed_ids, c.id) end

    local front = _build_line(front_cards, true,  "in_front_line")  -- face-up: AI dễ, lộ bài
    local back  = _build_line(back_cards,  true,  "in_back_line")
    local hand  = _rebuild_hand(state.omega_hand, deployed_ids)
    return front, back, hand, nil
end

-- ── Normal ───────────────────────────────────────────────────────────────────
-- AI cân bằng: 2 card face-down ở front, 1 card face-down ở back.

function _deploy_normal(state)
    local cards = _collect_cards(state.omega_hand)
    if #cards == 0 then
        return nil, nil, nil, "omega_hand is empty"
    end

    local front_cards = {}
    local back_cards  = {}
    for i, card in ipairs(cards) do
        if     i <= 2 then table.insert(front_cards, card)
        elseif i == 3 then table.insert(back_cards,  card)
        else break end
    end

    local deployed_ids = {}
    for _, c in ipairs(front_cards) do table.insert(deployed_ids, c.id) end
    for _, c in ipairs(back_cards)  do table.insert(deployed_ids, c.id) end

    local front = _build_line(front_cards, true,  "in_front_line")  -- front lộ, back ẩn
    local back  = _build_line(back_cards,  false, "in_back_line")
    local hand  = _rebuild_hand(state.omega_hand, deployed_ids)
    return front, back, hand, nil
end

-- ── Hard ─────────────────────────────────────────────────────────────────────
-- AI tấn công: 3 card face-up ở front (lộ bài, đe dọa),
--              2 card face-down ở back (bảo vệ ẩn).

function _deploy_hard(state)
    local cards = _collect_cards(state.omega_hand)
    if #cards == 0 then
        return nil, nil, nil, "omega_hand is empty"
    end

    local front_cards = {}
    local back_cards  = {}
    for i, card in ipairs(cards) do
        if     i <= 3 then table.insert(front_cards, card)
        elseif i <= 5 then table.insert(back_cards,  card)
        else break end
    end

    local deployed_ids = {}
    for _, c in ipairs(front_cards) do table.insert(deployed_ids, c.id) end
    for _, c in ipairs(back_cards)  do table.insert(deployed_ids, c.id) end

    local front = _build_line(front_cards, false, "in_front_line")  -- face-down: AI khó, ẩn bài
    local back  = _build_line(back_cards,  false, "in_back_line")   -- back ẩn
    local hand  = _rebuild_hand(state.omega_hand, deployed_ids)
    return front, back, hand, nil
end

-- ── Dispatcher chính ─────────────────────────────────────────────────────────
-- state      : battle session state (phải có state.omega_hand)
-- difficulty : "easy" | "normal" | "hard"
-- Trả về: omega_front_line, omega_back_line, omega_hand, err

function deploy_omega_cards(state, difficulty)
    if type(state) ~= "table" then
        return nil, nil, nil, "deploy_omega_cards: state must be a table"
    end
    if type(difficulty) ~= "string" then
        return nil, nil, nil, "deploy_omega_cards: difficulty must be a string"
    end
    if state.omega_hand == nil then
        return nil, nil, nil, "deploy_omega_cards: state.omega_hand is required"
    end

    if difficulty == "easy" then
        return _deploy_easy(state)
    elseif difficulty == "normal" then
        return _deploy_normal(state)
    elseif difficulty == "hard" then
        return _deploy_hard(state)
    else
        return nil, nil, nil, "deploy_omega_cards: unknown difficulty '" .. difficulty .. "' (easy|normal|hard)"
    end
end