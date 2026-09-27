-- 多字词选一、两次排第二；选到第三次后排第一。
local store = require("quick_memory_store")
local M = {}

function M.init(env)
    store.load()
end

function M.func(input, env)
    local code = env.engine.context.input:lower():gsub("[^a-z0-9]", "")
    local remembered = store.lookup(code)
    if not remembered then
        for cand in input:iter() do yield(cand) end
        return
    end

    local all, strong, weak = {}, {}, {}
    local index = 0
    for cand in input:iter() do
        index = index + 1
        table.insert(all, cand)
        local item = remembered[cand.text]
        if item then
            local target = store.is_strong(cand.text, item) and strong or weak
            table.insert(target, { cand = cand, score = store.score(item), index = index })
        end
        if index >= 300 then break end
    end

    local function by_score(a, b)
        if a.score == b.score then return a.index < b.index end
        return a.score > b.score
    end
    table.sort(strong, by_score)
    table.sort(weak, by_score)

    local yielded = {}
    local function emit(cand)
        if yielded[cand] then return end
        yielded[cand] = true
        yield(cand)
    end

    -- 已建立的首选保持第一；没有时保留原本的第一候选。
    if #strong > 0 then
        emit(strong[1].cand)
    elseif #all > 0 then
        emit(all[1])
    end

    -- 最新的一、两次选择在第二位，其余已有偏好随后排列。
    if #weak > 0 then emit(weak[1].cand) end
    for _, item in ipairs(strong) do emit(item.cand) end
    for _, item in ipairs(weak) do emit(item.cand) end
    for _, cand in ipairs(all) do emit(cand) end
end

return M
