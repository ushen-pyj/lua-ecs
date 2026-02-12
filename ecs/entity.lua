local Entity = {}

Entity.__index = function(self, key)
    local method = Entity[key]
    if method then return method end
    
    return self._world:get(self._id, key)
end

Entity.__newindex = function(self, key, value)
    if value == nil then
        self._world:remove(self._id, key)
    else
        self._world:add(self._id, key, value)
    end
end

function Entity:destroy()
    return self._world:destroy(self._id)
end

function Entity:has(name)
    return self._world:has(self._id, name)
end

function Entity:set(name, data)
    self._world:add(self._id, name, data)
    return self
end

return function(world, id)
    return setmetatable({ _id = id, _world = world }, Entity)
end
