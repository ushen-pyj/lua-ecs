local sparseset = require "sparseset"
local create_proxy = require "ecs.entity"
local View = require "ecs.view"
local Group = require "ecs.group"

local World = {}
World.__index = World

function World.new()
    local self = setmetatable({}, World)
    self.registry = sparseset.new_registry()
    self.component_sets = {}
    self.component_names = {}
    self.templates = {}
    self.systems = {}
    self.groups = {}
    return self
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
        self.component_sets[name]:remove(id)
    end
    self.registry:destroy(id)
end

function World:valid(id)
    return self.registry:valid(id)
end

function World:add(id, name, data)
    local set = self.component_sets[name]
    if not set then set = self:register_component(name) end
    
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

function World:get(id, name)
    local set = self.component_sets[name]
    return set and set:get(id)
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
    table.sort(components)
    local key = table.concat(components, "|")
    
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
