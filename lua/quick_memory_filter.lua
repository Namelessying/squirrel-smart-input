-- 渐进式本地学习：
-- 选过一次的词移动到原候选前两名之后；选过两次及以上则直接置前。
-- 次数优先，最近使用时间用于破同分。
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

    -- 两次以上的明确偏好永远排在云候选之前。
    for _, item in ipairs(strong) do emit(item.cand) end

    -- 保留原排序最靠前的两个候选，避免一次误选立刻压掉搜狗首选。
    local guarded = 0
    for _, cand in ipairs(all) do
        local item = remembered[cand.text]
        if not item or not store.is_strong(cand.text, item) then
            emit(cand)
            guarded = guarded + 1
            if guarded >= 2 then break end
        end
    end

    -- 一次选择的词进入首屏，排在上述两个候选之后。
    for _, item in ipairs(weak) do emit(item.cand) end
    for _, cand in ipairs(all) do emit(cand) end
end

return M
