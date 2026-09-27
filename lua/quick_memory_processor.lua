-- 所有选词都在实际上屏时记录一次，避免重复通知和翻页数字键误记。
local store = require("quick_memory_store")
local M = {}

function M.init(env)
    store.load()

    env.commit_connection = env.engine.context.commit_notifier:connect(function(context)
        local code = context.input or ""
        if #code < 2 then return end
        local selected = context:get_selected_candidate()
        if not selected or not selected.text or selected.text == "" then return end
        local committed = context:get_commit_text() or ""
        if committed == selected.text then
            store.record_selection(code, selected.text, selected.preedit or "")
        end
    end)
end

function M.fini(env)
    if env.commit_connection then env.commit_connection:disconnect() end
    env.commit_connection = nil
end

function M.func(key, env)
    if key:release() then return 2 end
    local context = env.engine.context
    if not context:has_menu() then return 2 end

    local repr = key:repr()
    if repr == "Control+Delete" or repr == "Shift+Delete" then
        local selected = context:get_selected_candidate()
        if selected then store.remove_by_text(selected.text) end
        return 2
    end

    return 2
end

return M
