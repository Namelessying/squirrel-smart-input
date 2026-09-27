-- 将用户已经选过的词直接作为高权重候选产生。
-- 多字词选一、两次进入第二位，第三次置顶；最近选择优先。
local store = require("quick_memory_store")
local M = {}

function M.init(env)
    store.load()
end

function M.func(input, seg, env)
    local code = (input or ""):lower():gsub("[^a-z0-9]", "")
    if #code < 2 then return end

    local remembered = store.lookup(code)
    if not remembered then return end

    local items = {}
    for text, item in pairs(remembered) do
        table.insert(items, {
            text = text,
            count = item.count or 0,
            score = store.score(item),
        })
    end
    table.sort(items, function(a, b)
        if a.score == b.score then return a.text < b.text end
        return a.score > b.score
    end)

    for index, item in ipairs(items) do
        local cand = Candidate("quick_memory", seg.start, seg._end, item.text, "")
        if store.is_strong(item.text, item) then
            cand.quality = 2200000000 - index
        else
            cand.quality = 1000000000 - index
        end
        yield(cand)
    end
end

return M
