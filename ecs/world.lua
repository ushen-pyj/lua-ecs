local sparseset = require "sparseset"
local create_proxy = require "ecs.entity"
local View = require "ecs.view"
local Group = require "ecs.group"

local World = {}
World.__index = World

local CComponent = require "ecs.c_component"

local C_TYPES = {
    int = { size = 4, pack = "i4" },
    float = { size = 4, pack = "f" },
    double = { size = 8, pack = "d" },
    byte = { size = 1, pack = "I1" },
    bool = { size = 1, pack = "I1" }, -- 0 or 1
}

function World.new()
    local self = setmetatable({}, World)
    self.registry = sparseset.new_registry()
    self.component_sets = {}
    self.component_names = {}
    self.c_descriptors = {}
    self.templates = {}
    self.systems = {}
    self.groups = {}
    return self
end

function World:register(decl)
    if type(decl) == "string" then
        return self:register_component(decl)
    end
    
    local name = decl.name
    if not name then error("Component must have a name") end
    
    if self.component_sets[name] then return self.component_sets[name] end
    
    -- Check if C component
    local is_c = false
    local fields = {}
    local stride = 0
    
    for _, s in ipairs(decl) do
        local fname, ftype = s:match("([%w_]+):([%w_]+)")
        if fname and ftype then
            local info = C_TYPES[ftype]
            if not info then error("Unknown type: "..ftype) end
            is_c = true
            fields[fname] = { offset = stride, type = ftype }
            stride = stride + info.size
        end
    end
    
    local set
    if is_c then
        set = sparseset.new_set(stride)
        self.c_descriptors[name] = { stride = stride, fields = fields }
    else
        set = sparseset.new_set()
    end
    
    self.component_sets[name] = set
    table.insert(self.component_names, name)
    return set
end

function World:register_component(name)
    if self.component_sets[name] then return self.component_sets[name] end
    local set = sparseset.new_set()
    self.component_sets[name] = set
    table.insert(self.component_names, name)
    return set
end

function World:template(name, data)
    self.templates[name] = data
end

function World:create(components)
    local id = self.registry:create()
    if components then
        for name, data in pairs(components) do
            self:add(id, name, data)
        end
    end
    return id
end

function World:destroy(id)
    for _, name in ipairs(self.component_names) do
        if self:has(id, name) then
            self:update_groups_on_remove(id, name)
            self.component_sets[name]:remove(id)
        end
    end
    self.registry:destroy(id)
end

function World:valid(id)
    return self.registry:valid(id)
end

function World:add(id, name, data)
    local set = self.component_sets[name]
    if not set then set = self:register_component(name) end
    
    local desc = self.c_descriptors[name]
    
    if desc then
        -- C Component
        -- If data is a table, fill fields
        -- Insert placeholder (zeroed) first
        if set:insert(id, nil) then
             if type(data) == "table" then
                 for k, v in pairs(data) do
                     local field = desc.fields[k]
                     if field then
                         set:set_field(id, field.offset, field.type, v)
                     end
                 end
             -- If data is string (packed binary), use it directly?
             -- Our set:insert Lua binding handles string now.
             elseif type(data) == "string" then
                 set:insert(id, data)
             end
             self:update_groups_on_add(id, name)
        end
        return self:get(id, name) -- Return proxy
    else
        -- Lua Component logic
        if data == true or data == nil then
            local tpl = self.templates[name]
            if tpl then
                local newData = {}
                for k,v in pairs(tpl) do newData[k] = v end
                data = newData
            else
                data = true
            end
        end
        
        set:insert(id, data)
        self:update_groups_on_add(id, name)
        return data
    end
end

function World:get(id, name)
    local set = self.component_sets[name]
    if not set or not set:contains(id) then return nil end
    
    local desc = self.c_descriptors[name]
    if desc then
        return CComponent.new(self, id, name, desc)
    else
        return set:get(id)
    end
end

function World:has(id, name)
    local set = self.component_sets[name]
    return set and set:contains(id) or false
end

function World:remove(id, name)
    local set = self.component_sets[name]
    if set then 
        self:update_groups_on_remove(id, name)
        set:remove(id) 
    end
end

function World:proxy(id)
    if not self:valid(id) then return nil end
    return create_proxy(self, id)
end

function World:view(...)
    return View.new(self, {...})
end

function World:system(names, callback)
    table.insert(self.systems, {names = names, fn = callback})
end

function World:group(...)
    local components = {...}
    local sorted_names = {...}
    table.sort(sorted_names)
    local key = table.concat(sorted_names, "|")
    
    if self.groups[key] then return self.groups[key] end
    
    local group = Group.new(self, components)
    self.groups[key] = group
    table.insert(self.groups, group)
    return group
end

function World:update_groups_on_add(id, name)
    for _, group in ipairs(self.groups) do
        group:on_add(id, name)
    end
end

function World:update_groups_on_remove(id, name)
    for _, group in ipairs(self.groups) do
        group:on_remove(id, name)
    end
end

function World:update(dt)
    for _, sys in ipairs(self.systems) do
        local view = self:view(table.unpack(sys.names))
        for id, comps in view:each() do
            sys.fn(dt, id, table.unpack(comps, 1, view.n))
        end
    end
end

return World
