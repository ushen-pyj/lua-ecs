local View = {}
View.__index = View

function View.new(world, names)
    local self = setmetatable({}, View)
    self.world = world
    self.names = names
    self.n = #names

    return self
end

local CComponent = require "ecs.c_component"

function View:resolve_sets()
    local sets = {}
    local min_idx = 1
    local min_size = math.huge

    for i = 1, self.n do
        local set = self.world.component_sets[self.names[i]]
        if not set then
            return nil
        end
        sets[i] = set
        local sz = set:size()
        if sz < min_size then
            min_size = sz
            min_idx = i
        end
    end

    self.sets = sets
    self.min_idx = min_idx
    return true
end

function View:each()
    if not self:resolve_sets() then
        return function() end
    end
    
    local world = self.world
    local n = self.n
    local min_idx = self.min_idx
    local sets = self.sets
    local names = self.names
    
    local flyweights = {}
    for j=1, n do
        local desc = world.c_descriptors[names[j]]
        if desc then
            flyweights[j] = CComponent.new(world, 0, names[j], desc)
        end
    end

    local iter_func, state, var = sets[min_idx]:iter()
    
    local results = {}

    return function()
        while true do
            local i, id, data = iter_func(state, var)
            if not i then return nil end
            var = i
            
            local match = true
            for j=1, n do
                local d
                if j == min_idx then
                    d = data
                else
                    d = sets[j]:get(id)
                    if d == nil then
                        match = false
                        break
                    end
                end
                
                local fw = flyweights[j]
                if fw then
                    fw:_bind(id)
                    results[j] = fw
                else
                    results[j] = d
                end
            end
            
            if match then
                return id, table.unpack(results, 1, n)
            end
        end
    end
end

return View
