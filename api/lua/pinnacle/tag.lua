-- This Source Code Form is subject to the terms of the Mozilla Public
-- License, v. 2.0. If a copy of the MPL was not distributed with this
-- file, You can obtain one at https://mozilla.org/MPL/2.0/.

local client = require("pinnacle.grpc.client")

---The protobuf absolute path prefix
local prefix = "pinnacle.tag." .. client.version .. "."
local service = prefix .. "TagService"

---@type table<string, { request_type: string?, response_type: string? }>
---@enum (key) TagServiceMethod
local rpc_types = {
    SetActive = {},
    SwitchTo = {},
    Add = {
        response_type = "AddResponse",
    },
    Remove = {},
    Get = {
        response_type = "GetResponse",
    },
    GetProperties = {
        response_type = "GetPropertiesResponse",
    },
}

---Build GrpcRequestParams
---@param method TagServiceMethod
---@param data table
---@return GrpcRequestParams
local function build_grpc_request_params(method, data)
    local req_type = rpc_types[method].request_type
    local resp_type = rpc_types[method].response_type

    ---@type GrpcRequestParams
    return {
        service = service,
        method = method,
        request_type = req_type and prefix .. req_type or prefix .. method .. "Request",
        response_type = resp_type and prefix .. resp_type,
        data = data,
    }
end

local set_or_toggle = {
    SET = 1,
    [true] = 1,
    UNSET = 2,
    [false] = 2,
    TOGGLE = 3,
}

---@nodoc
---@class TagHandleModule
local tag_handle = {}

---A tag handle.
---
---This is a handle that allows manipulation of a tag.
---
---This can be retrieved through the various `get` functions in the `Tag` module.
---@classmod
---@class TagHandle
---@field id integer
local TagHandle = {}

---Tag management.
---
---This module provides utilities for creating and manipulating tags.
---
---A tag is a sort of marker for each of your windows. It allows you to present windows in ways that
---traditional workspaces cannot.
---
---More specifically:
---
--- - A window can have multiple tags.
---   - This means that you can have one window show up across multiple "workspaces" if you come something like i3.
--- - An output can display multiple tags at once.
---   - This allows you to toggle a tag and have windows on both tags display at once. This is helpful if you, say, want to reference a browser window while coding; you toggle your browser's tag and temporarily reference it while you work without having to change screens.
---
---If you need to get tags beyond the first with the same name, use the `get` method and find what you need.
---@class Tag
---@field private handle TagHandleModule
local tag = {}
tag.handle = tag_handle

---Get all tags across all outputs.
---
---@return TagHandle[]
function tag.get_all()
    local response = client.unary_request(build_grpc_request_params("Get", {}))

    ---@type TagHandle[]
    local handles = {}

    for _, id in ipairs(response.tag_ids or {}) do
        table.insert(handles, tag_handle.new(id))
    end

    return handles
end

---Get the tag with the given name and output.
---
---If `output` is not specified, this uses the focused output.
---
---If an output has more than one tag with the same name, this returns the first.
---
---### Example
---```lua
--- -- Get tags on the focused output
---local tag = Tag.get("Tag")
---
--- -- Get tags on a specific output
---local tag_on_hdmi1 = Tag.get("Tag", Output:get_by_name("HDMI-1"))
---```
---
---@param name string
---@param output OutputHandle?
---
---@return TagHandle | nil
function tag.get(name, output)
    output = output or require("pinnacle.output").get_focused()

    if not output then
        return
    end

    local handles = tag.get_all()

    ---@type (fun(): TagProperties)[]
    local requests = {}

    for i, handle in ipairs(handles) do
        requests[i] = function()
            return handle:props()
        end
    end

    local props = require("pinnacle.util").batch(requests)

    for i, prop in ipairs(props) do
        if prop.output and prop.output.name == output.name and prop.name == name then
            return handles[i]
        end
    end

    return nil
end

---Add tags with the given names to the specified output.
---
---Returns handles to the created tags.
---
---### Example
---```lua
---local tags = Tag.add(Output.get_by_name("HDMI-1"), "1", "2", "Buckle", "Shoe")
---
--- -- With a table
---local tag_names = { "1", "2", "Buckle", "Shoe" }
---local tags = Tag.add(Output.get_by_name("HDMI-1"), tag_names)
---```
---
---@param output OutputHandle
---@param ... string
---
---@return TagHandle[] tags Handles to the created tags
---
---@overload fun(output: OutputHandle, tag_names: string[])
function tag.add(output, ...)
    local tag_names = { ... }
    if type(tag_names[1]) == "table" then
        tag_names = tag_names[1] --[=[@as string[]]=]
    end

    local response = client.unary_request(build_grpc_request_params("Add", {
        output_name = output.name,
        tag_names = tag_names,
    }))

    ---@type TagHandle[]
    local handles = {}

    for _, id in ipairs(response.tag_ids) do
        table.insert(handles, tag_handle.new(id))
    end

    return handles
end

---Remove the given tags.
---
---### Example
---```lua
---local tags = Tag.add(Output.get_by_name("HDMI-1"), "1", "2", "Buckle", "Shoe")
---
---Tag.remove(tags) -- "HDMI-1" no longer has those tags
---```
---
---@param tags TagHandle[]
function tag.remove(tags)
    ---@type integer[]
    local ids = {}

    for _, tg in ipairs(tags) do
        table.insert(ids, tg.id)
    end

    client.unary_request(build_grpc_request_params("Remove", { tag_ids = ids }))
end

---Remove this tag.
---
---### Example
---```lua
---local tags = Tag.add(Output.get_by_name("HDMI-1"), "1", "2", "Buckle", "Shoe")
---
---tags[2]:remove()
---tags[4]:remove()
--- -- "HDMI-1" now only has tags "1" and "Buckle"
---```
function TagHandle:remove()
    client.unary_request(build_grpc_request_params("Remove", { tag_ids = { self.id } }))
end

---Activate this tag and deactivate all other ones on the same output.
---
---### Example
---```lua
--- -- Assume the focused output has the following inactive tags and windows:
--- --  - "1": Alacritty
--- --  - "2": Firefox, Discord
--- --  - "3": Steam
---Tag.get("2"):switch_to() -- Displays Firefox and Discord
---Tag.get("3"):switch_to() -- Displays Steam
---```
function TagHandle:switch_to()
    client.unary_request(build_grpc_request_params("SwitchTo", { tag_id = self.id }))
end

---Set whether or not this tag is active.
---
---### Example
---```lua
--- -- Assume the focused output has the following inactive tags and windows:
--- --  - "1": Alacritty
--- --  - "2": Firefox, Discord
--- --  - "3": Steam
---Tag.get("2"):set_active(true)  -- Displays Firefox and Discord
---Tag.get("3"):set_active(true)  -- Displays Firefox, Discord, and Steam
---Tag.get("2"):set_active(false) -- Displays Steam
---```
---
---@param active boolean
function TagHandle:set_active(active)
    client.unary_request(
        build_grpc_request_params("SetActive", { tag_id = self.id, set_or_toggle = set_or_toggle[active] })
    )
end

---Toggle this tag's active state.
---
---### Example
---```lua
--- -- Assume the focused output has the following inactive tags and windows:
--- --  - "1": Alacritty
--- --  - "2": Firefox, Discord
--- --  - "3": Steam
---Tag.get("2"):toggle_active() -- Displays Firefox and Discord
---Tag.get("2"):toggle_active() -- Displays nothing
---```
function TagHandle:toggle_active()
    client.unary_request(
        build_grpc_request_params("SetActive", { tag_id = self.id, set_or_toggle = set_or_toggle.TOGGLE })
    )
end

---@class TagProperties
---@field active boolean? Whether or not the tag is currently being displayed
---@field name string? The name of the tag
---@field output OutputHandle? The output the tag is on
---@field windows WindowHandle[] The windows that have this tag

---Get all properties of this tag.
---
---@return TagProperties
function TagHandle:props()
    local response = client.unary_request(build_grpc_request_params("GetProperties", { tag_id = self.id }))

    return {
        active = response.active,
        name = response.name,
        ---@diagnostic disable-next-line: invisible
        output = response.output_name and require("pinnacle.output").handle.new(response.output_name),
        ---@diagnostic disable-next-line: invisible
        windows = require("pinnacle.window").handle.new_from_table(response.window_ids or {}),
    }
end

---Get whether or not this tag is being displayed.
---
---Shorthand for `handle:props().active`.
---
---@return boolean?
function TagHandle:active()
    return self:props().active
end

---Get this tag's name.
---
---Shorthand for `handle:props().name`.
---
---@return string?
function TagHandle:name()
    return self:props().name
end

---Get the output this tag is on.
---
---Shorthand for `handle:props().output`.
---
---@return OutputHandle?
function TagHandle:output()
    return self:props().output
end

---Get the windows that have this tag.
---
---Shorthand for `handle:props().windows`.
---
---@return WindowHandle[]
function TagHandle:windows()
    return self:props().windows
end

---@nodoc
---Create a new `TagHandle` from an id.
---@param tag_id integer
---@return TagHandle
function tag_handle.new(tag_id)
    ---@type TagHandle
    local self = {
        id = tag_id,
    }
    setmetatable(self, { __index = TagHandle })
    return self
end

---@nodoc
---@param tag_ids integer[]
---@return TagHandle[]
function tag_handle.new_from_table(tag_ids)
    ---@type TagHandle[]
    local handles = {}

    for _, id in ipairs(tag_ids) do
        table.insert(handles, tag_handle.new(id))
    end

    return handles
end

return tag
