
local Component = {}

function Component.new(world, id, name, desc)
    local proxy = {
        _world = world,
        _id = id,
        _name = name,
        _desc = desc
    }
    setmetatable(proxy, Component)
    return proxy
end

function Component:__index(key)
    local desc = rawget(self, "_desc")
    local field = desc.fields[key]
    if field then
        local world = rawget(self, "_world")
        local name = rawget(self, "_name")
        local id = rawget(self, "_id")
        local set = world.component_sets[name]
        return set:get_field(id, field.offset, field.type)
    end
    return Component[key]
end

function Component:__newindex(key, value)
    local desc = rawget(self, "_desc")
    local field = desc.fields[key]
    if field then
        local world = rawget(self, "_world")
        local name = rawget(self, "_name")
        local id = rawget(self, "_id")
        local set = world.component_sets[name]
        set:set_field(id, field.offset, field.type, value)
    else
        rawset(self, key, value)
    end
end

return Component
