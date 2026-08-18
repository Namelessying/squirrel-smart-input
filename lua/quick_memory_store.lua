-- 本地快速记忆：一次选择后，把该词在相同编码及首字母编码下强力置前。
local M = {
    loaded = false,
    data = {},
    tick = 0,
    last_signature = "",
    last_record_time = 0,
}

local function clean_code(code)
    return (code or ""):lower():gsub("[^a-z0-9]", "")
end

-- 只让汉字单字参与快速学习，避免标点、Emoji、假名和单个字母污染记忆库。
local function is_single_han(text)
    if not text or utf8.len(text) ~= 1 then return false end
    local cp = utf8.codepoint(text)
    return cp == 0x3007
        or (cp >= 0x3400 and cp <= 0x4DBF)
        or (cp >= 0x4E00 and cp <= 0x9FFF)
        or (cp >= 0xF900 and cp <= 0xFAFF)
        or (cp >= 0x20000 and cp <= 0x2FA1F)
end

function M.load()
    if M.loaded then return end
    M.loaded = true
    local root = rime_api:get_user_data_dir()
    M.path = root .. "/quick_memory.tsv"

    local f = io.open(M.path, "r")
    if f then
        for line in f:lines() do
            local code, text, count, tick = line:match("^([^\t]+)\t([^\t]+)\t(%d+)\t(%d+)$")
            if code and text then
                M.data[code] = M.data[code] or {}
                M.data[code][text] = { count = tonumber(count), tick = tonumber(tick) }
                M.tick = math.max(M.tick, tonumber(tick))
            end
        end
        f:close()
    end

end

local function save()
    if not M.path then return end
    local tmp = M.path .. ".tmp"
    local f = io.open(tmp, "w")
    if not f then return end
    local codes = {}
    for code in pairs(M.data) do table.insert(codes, code) end
    table.sort(codes)
    for _, code in ipairs(codes) do
        local texts = {}
        for text in pairs(M.data[code]) do table.insert(texts, text) end
        table.sort(texts)
        for _, text in ipairs(texts) do
            local item = M.data[code][text]
            f:write(string.format("%s\t%s\t%d\t%d\n", code, text, item.count, item.tick))
        end
    end
    f:close()
    os.rename(tmp, M.path)
end

local function remember(code, text)
    code = clean_code(code)
    if #code < 2 or not text then return false end
    local length = utf8.len(text)
    if not length or (length < 2 and not is_single_han(text)) then return false end
    M.data[code] = M.data[code] or {}
    local item = M.data[code][text] or { count = 0, tick = 0 }
    M.tick = M.tick + 1
    item.count = item.count + 1
    item.tick = M.tick
    M.data[code][text] = item
    return true
end

function M.record_selection(raw_code, text, preedit)
    M.load()
    local signature = clean_code(raw_code) .. "\t" .. (text or "")
    local current_time = rime_api.get_time_ms and rime_api.get_time_ms() or os.time() * 1000
    if signature == M.last_signature and current_time - M.last_record_time < 250 then
        return false
    end
    M.last_signature = signature
    M.last_record_time = current_time

    local codes = {}
    codes[clean_code(raw_code)] = true

    local syllables = {}
    for syllable in (preedit or ""):gmatch("[A-Za-z]+") do
        table.insert(syllables, syllable:lower())
    end
    if #syllables > 0 then
        codes[table.concat(syllables, "")] = true
    end
    if #syllables > 1 then
        local initials = {}
        for _, syllable in ipairs(syllables) do
            table.insert(initials, syllable:sub(1, 1))
        end
        codes[table.concat(initials, "")] = true
    end
    local changed = false
    for code in pairs(codes) do
        if remember(code, text) then changed = true end
    end
    if changed then save() end
    return changed
end

function M.lookup(code)
    M.load()
    return M.data[clean_code(code)]
end

function M.remove(code, text)
    M.load()
    code = clean_code(code)
    local bucket = M.data[code]
    if not bucket or not bucket[text] then return false end
    bucket[text] = nil
    if next(bucket) == nil then M.data[code] = nil end
    save()
    return true
end

-- 清除一个词在原始码、全拼及首字母简拼下的全部学习记录。
function M.remove_by_text(text)
    M.load()
    if not text or text == "" then return false end

    local changed = false
    local empty_codes = {}
    for code, bucket in pairs(M.data) do
        if bucket[text] then
            bucket[text] = nil
            changed = true
            if next(bucket) == nil then table.insert(empty_codes, code) end
        end
    end
    for _, code in ipairs(empty_codes) do M.data[code] = nil end
    if changed then save() end
    return changed
end

function M.score(item)
    return item.count * 1000000000 + item.tick
end

-- 汉字单字选过一次即视为强偏好；多字词仍需两次，防止误选压过云候选。
function M.is_strong(text, item)
    local count = item and item.count or 0
    return count >= 2 or (count >= 1 and is_single_han(text))
end

return M
