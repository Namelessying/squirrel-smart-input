-- 纠错拼写仍给出候选，并只在确实像错拼时显示正确拼音。
local M = {}

function M.init(env)
    env.typo_map = {}
    local f = io.open(rime_api:get_user_data_dir() .. "/typo_corrections.tsv", "r")
    if not f then return end
    for line in f:lines() do
        local wrong, correct = line:match("^([a-z]+)\t([a-z]+)$")
        if wrong and correct then env.typo_map[wrong] = correct end
    end
    f:close()
end

local function compact(s)
    return (s or ""):lower():gsub("[^a-z]", "")
end

local function initial_codes(pinyin)
    local short, digraph = {}, {}
    for syllable in pinyin:gmatch("[a-z]+") do
        table.insert(short, syllable:sub(1, 1))
        if syllable:match("^[zcs]h") then
            table.insert(digraph, syllable:sub(1, 2))
        else
            table.insert(digraph, syllable:sub(1, 1))
        end
    end
    return table.concat(short, ""), table.concat(digraph, "")
end

function M.func(input, env)
    local raw = compact(env.engine.context.input)
    for cand in input:iter() do
        local genuine = cand:get_genuine()
        local wrapped = cand.comment or ""
        -- 前一个 corrector 只会为确实存在的读音纠错留下纯拼音。
        local pronunciation_hint = genuine.comment or ""
        if not pronunciation_hint:match("^[a-zv ]+$") then pronunciation_hint = "" end
        genuine.comment = ""

        local mapped = env.typo_map[raw]
        if mapped and cand.type == "table" and compact(cand.preedit) == raw then
            genuine.comment = mapped
        end
        -- 雾凇的主翻译器把完整拼音放在外层候选的［］注释里；
        -- 前一个 corrector 可能同时改写 genuine.comment，因此优先读外层原始拼音。
        local pinyin = wrapped:match("^［([a-zv ]+)］$")
        if not pinyin then
            local comment = genuine.comment or ""
            pinyin = comment:match("^([a-zv ]+)$")
        end
        if pinyin then
            local correct = compact(pinyin)
            local short, digraph = initial_codes(pinyin)
            local is_abbrev = raw == short or raw == digraph
            local is_prefix = #raw > 0 and correct:sub(1, #raw) == raw
            local is_partial = #correct > 0 and raw:sub(1, #correct) == correct
            local covers_input = compact(cand.preedit) == raw
            local looks_like_typo =
                #raw > 0 and raw ~= correct and not is_abbrev and not is_prefix and not is_partial
                and covers_input
                and #raw >= math.max(2, #correct - 2)
                and #raw <= #correct + 2
            if looks_like_typo then
                genuine.comment = pinyin
            end
        end
        if genuine.comment == "" and pronunciation_hint ~= "" then
            genuine.comment = pronunciation_hint
        end
        yield(cand)
    end
end

return M
