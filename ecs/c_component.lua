local Component = {}

function Component.new(world, id, name, desc)
    local proxy = {
        _world = world,
        _id = id,
        _name = name,
        _desc = desc,
        _set = world.component_sets[name]
    }
    return setmetatable(proxy, Component)
end

function Component:_bind(id)
    self._id = id
end

function Component:__index(key)
    local field = self._desc.fields[key]
    if field then
        return self._set:get_field(self._id, field.offset, field.type)
    end
    return Component[key]
end

function Component:__newindex(key, value)
    local field = self._desc.fields[key]
    if field then
        self._set:set_field(self._id, field.offset, field.type, value)
    else
        error(string.format(
            "Unknown field '%s' for C-component '%s'. Valid fields: %s",
            key,
            self._name,
            table.concat(self._desc.field_names, ", ")))
    end
end

return Component
