-- 唯一的日语快捷词：中文模式输入 no 时，将「の」固定为首选。
local M = {}

function M.func(input, seg, env)
    if input ~= "no" then return end

    local cand = Candidate("no_kana", seg.start, seg._end, "の", "")
    cand.preedit = input
    cand.quality = 3000000000
    yield(cand)
end

return M
