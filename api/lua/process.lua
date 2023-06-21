local process = {}

---Spawn a process with an optional callback for its stdout and stderr.
---@param command string|string[] The command as one whole string or a table of each of its arguments
---@param callback fun(stdout: string?, stderr: string?, exit_code: integer?, exit_msg: string?)? A callback to do something whenever the process's stdout or stderr print a line. Only one will be non-nil at a time.
function process.spawn(command, callback)
    ---@type integer|nil
    local callback_id = nil

    if callback ~= nil then
        table.insert(CallbackTable, function(args)
            local args = args or {}
            callback(args.stdout, args.stderr, args.exit_code, args.exit_msg)
        end)
        callback_id = #CallbackTable
    end

    local command_str = command
    local command = command
    if type(command_str) == "string" then
        command = {}
        for i in string.gmatch(command_str, "%S+") do
            table.insert(command, i)
        end
    end

    SendMsg({
        Spawn = {
            command = command,
            callback_id = callback_id,
        },
    })
end

return process