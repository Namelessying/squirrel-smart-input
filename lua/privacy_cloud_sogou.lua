-- 可选搜狗云候选；公开版默认关闭，只有用户主动开启后才会联网。
-- 使用 HTTPS；连接失败后短暂冷却，避免连续阻塞输入。
-- 仅发送当前未上屏的拼音串，不读取或上传用户词典与输入历史。

local M = {}

local user_dir = rime_api.get_user_data_dir()
package.cpath = user_dir .. "/lua/?.so;" .. package.cpath

local http_ok, http = pcall(require, "simplehttp")
if not http_ok then http = nil end

-- 联网宁可少等一次，也不阻塞连续输入；查到的结果会永久落地。
if http then http.TIMEOUT = 0.20 end

local cache = {}
local cache_path = user_dir .. "/sogou_cloud_cache.tsv"
local network_disabled_until = 0
local empty_cache = {}
local empty_cache_ttl_ms = 60000

local function now_ms()
    if rime_api.get_time_ms then return rime_api.get_time_ms() end
    return os.time() * 1000
end

local function clean_field(value)
    local cleaned = (value or ""):gsub("[\t\r\n]", "")
    return cleaned
end

local function load_persistent_cache()
    local file = io.open(cache_path, "r")
    if not file then return end
    for line in file:lines() do
        local fields = {}
        for field in line:gmatch("[^\t]+") do
            table.insert(fields, field)
        end
        local code = table.remove(fields, 1)
        if code and code:match("^[a-z']+$") and #fields > 0 then
            cache[code] = { words = fields, local_hit = true }
        end
    end
    file:close()
end

local function cache_put(key, words)
    cache[key] = { words = words, local_hit = true }
    if #words == 0 then return end

    local file = io.open(cache_path, "a")
    if file then
        file:write(clean_field(key))
        for i = 1, math.min(#words, 5) do
            file:write("\t", clean_field(words[i]))
        end
        file:write("\n")
        file:close()
    end
end

load_persistent_cache()

local function checksum_byte(data)
    local value = 0
    for i = 1, #data do
        value = value ~ string.byte(data, i)
    end
    return string.char(value)
end

local function serialize_keys(keys)
    local protocol_header = "\0\5\0\0\0\0\1"
    local total_len = #protocol_header + #keys + 3
    local data = string.char(total_len) .. protocol_header .. string.char(#keys) .. keys
    return data .. checksum_byte(data)
end

local function utf16le_to_utf8(data)
    local out = {}
    local i = 1
    while i + 1 <= #data do
        local lo, hi = string.byte(data, i, i + 1)
        local codepoint = lo + hi * 256
        i = i + 2
        if codepoint >= 0xD800 and codepoint <= 0xDBFF and i + 1 <= #data then
            local lo2, hi2 = string.byte(data, i, i + 1)
            local low_surrogate = lo2 + hi2 * 256
            if low_surrogate >= 0xDC00 and low_surrogate <= 0xDFFF then
                codepoint = 0x10000 + (codepoint - 0xD800) * 0x400 + (low_surrogate - 0xDC00)
                i = i + 2
            end
        end
        local ok, ch = pcall(utf8.char, codepoint)
        if ok then table.insert(out, ch) end
    end
    return table.concat(out)
end

local function parse_result(result)
    local words = {}
    if type(result) ~= "string" or #result < 22 then return words end
    if string.byte(result, 1) + 2 ~= #result then return words end

    local num_words = string.unpack("<H", string.sub(result, 0x12 + 1, 0x12 + 2))
    if num_words < 1 or num_words > 32 then return words end

    local pos = 0x14
    for _ = 1, num_words do
        if pos + 2 > #result then break end
        local str_len = string.unpack("<H", string.sub(result, pos + 1, pos + 2))
        pos = pos + 2
        if str_len > 0 and pos + str_len <= #result then
            table.insert(words, utf16le_to_utf8(string.sub(result, pos + 1, pos + str_len)))
        end
        pos = pos + str_len

        if pos + 2 > #result then break end
        local unknown_len = string.unpack("<H", string.sub(result, pos + 1, pos + 2))
        pos = pos + unknown_len + 2

        if pos + 2 > #result then break end
        unknown_len = string.unpack("<H", string.sub(result, pos + 1, pos + 2))
        pos = pos + unknown_len + 3
    end
    return words
end

local function request_words(input)
    local cached = cache[input]
    if cached then return cached.words, "local" end
    if not http then return {}, "module-unavailable" end

    -- 成功请求但无候选的编码，在本次会话内短暂记住。
    -- 避免用户回删、重打同一串时反复等待网络；一分钟后自动重试。
    local empty_at = empty_cache[input]
    if empty_at then
        if now_ms() - empty_at < empty_cache_ttl_ms then
            return {}, "negative"
        end
        empty_cache[input] = nil
    end

    -- 断网或接口异常后暂停 30 秒，避免每个按键都重复等待超时。
    if now_ms() < network_disabled_until then return {}, "cooldown" end

    local path = "/web_ime/mobile.php?durtot=0&h=000000000000000&r=store_mf_wandoujia&v=3.7"
    local data = serialize_keys(input)
    local reply, code = http.request("https://shouji.sogou.com" .. path, data)
    if code ~= 200 then
        network_disabled_until = now_ms() + 30000
        return {}, "network-error"
    end

    local words = parse_result(reply)
    if #words > 0 then
        cache_put(input, words)
    else
        empty_cache[input] = now_ms()
    end
    return words, "network"
end

function M.func(input, seg, env)
    if not env.engine.context:get_option("cloud_input") then return end
    if #input < 2 or #input > 32 or not string.match(input, "^[a-z']+$") then return end

    local words, source = request_words(input)
    local is_initials = not input:match("[aeiouv]")
    for i = 1, math.min(#words, 5) do
        local comment = ""
        -- 实时与缓存使用同一权重，避免同一码前后两次候选顺序抖动。
        local base_quality = 2000000000
        if is_initials then base_quality = base_quality + 10 end
        local candidate = Candidate("cloud", seg.start, seg._end, words[i], comment)
        candidate.quality = base_quality - i * 0.01
        yield(candidate)
    end
end

return M
