
local Group = {}
Group.__index = Group

function Group.new(world, owned, filters)
    local self = setmetatable({}, Group)
    self.world = world
    self.owned = owned
    self.filters = filters or {}
    self.size = 0

    self.components = {}
    for _, name in ipairs(self.owned) do table.insert(self.components, name) end
    for _, name in ipairs(self.filters) do table.insert(self.components, name) end

    self.owned_sets = {}
    for _, name in ipairs(self.owned) do
        self.owned_sets[name] = world:register_component(name)
    end
    
    self.filter_sets = {}
    for _, name in ipairs(self.filters) do
        self.filter_sets[name] = world:register_component(name)
    end
    
    self:initialize()
    return self
end

function Group:initialize()
    local leader_name = self.owned[1] or self.filters[1]
    local leader_set = self.owned_sets[leader_name] or self.filter_sets[leader_name]
    
    local count = leader_set:size()
    local i = 1
    while i <= count do
        local id = leader_set:at(i)
        if self:match(id) then
            self:add_to_group(id)
        end
        i = i + 1
    end
end

function Group:owns(component_name)
    for _, name in ipairs(self.owned) do
        if name == component_name then return true end
    end
    for _, name in ipairs(self.filters) do
        if name == component_name then return true end
    end
    return false
end

function Group:match(id)
    for _, set in pairs(self.owned_sets) do
        if not set:contains(id) then return false end
    end
    for _, set in pairs(self.filter_sets) do
        if not set:contains(id) then return false end
    end
    return true
end

function Group:on_add(id, component_name)
    if not self:owns(component_name) then return end
    if self:match(id) and not self:is_in_group(id) then
        self:add_to_group(id)
    end
end

function Group:on_remove(id, component_name)
    if not self:owns(component_name) then return end
    if self:is_in_group(id) then
        self:remove_from_group(id)
    end
end

function Group:is_in_group(id)
    local leader_name = self.owned[1] or self.filters[1]
    local leader_set = self.owned_sets[leader_name] or self.filter_sets[leader_name]
    local pos = leader_set:index_of(id)
    return pos and pos <= self.size
end

function Group:add_to_group(id)
    local target_pos = self.size + 1
    for _, set in pairs(self.owned_sets) do
        local current_pos = set:index_of(id)
        if current_pos then 
            set:swap(current_pos, target_pos)
        end
    end
    self.size = self.size + 1
end

function Group:remove_from_group(id)
    local target_pos = self.size
    for _, set in pairs(self.owned_sets) do
        local current_pos = set:index_of(id)
        if current_pos then 
            set:swap(current_pos, target_pos)
        end
    end
    self.size = self.size - 1
end

function Group:sort(comparator)
    local size = self.size
    if size <= 1 then return end
    
    local leader_name = self.owned[1] or self.filters[1]
    local leader_set = self.owned_sets[leader_name] or self.filter_sets[leader_name]
    
    local ids = {}
    for i = 1, size do
        ids[i] = (leader_set:at(i))
    end
    
    table.sort(ids, function(a, b)
        return comparator(self.world, a, b)
    end)
    
    for i = 1, size do
        local target_id = ids[i]
        local current_pos = leader_set:index_of(target_id)
        if current_pos ~= i then
            for _, set in pairs(self.owned_sets) do
                set:swap(current_pos, i)
            end
        end
    end
end

local CComponent = require "ecs.c_component"

function Group:each()
    local size = self.size
    if size == 0 then return function() end end

    local world = self.world
    local components = self.components
    local num_comps = #components
    
    local sets = {}
    local is_owned = {}
    local flyweights = {}
    
    for i, name in ipairs(components) do
        sets[i] = self.owned_sets[name] or self.filter_sets[name]
        is_owned[i] = self.owned_sets[name] ~= nil
        
        local desc = world.c_descriptors[name]
        if desc then
            flyweights[i] = CComponent.new(world, 0, name, desc)
        end
    end

    local leader_name = self.owned[1] or self.filters[1]
    local leader_set = self.owned_sets[leader_name] or self.filter_sets[leader_name]
    local iter_func, state, var = leader_set:iter()

    local results = {} 

    return function()
        if var >= size then return nil end
        local idx, id, data = iter_func(state, var)
        var = idx
        
        for i = 1, num_comps do
            local d
            if is_owned[i] then
                if i == 1 and sets[i] == leader_set then
                    d = data
                else
                    local _, val = sets[i]:at(idx)
                    d = val
                end
            else
                d = sets[i]:get(id)
            end
            
            local fw = flyweights[i]
            if fw then
                fw:_bind(id)
                results[i] = fw
            else
                results[i] = d
            end
        end
        return id, table.unpack(results, 1, num_comps)
    end
end

function Group:iter()
    local it = self:each()
    return function()
        local r = {it()}
        if not r[1] then return nil end
        local id = table.remove(r, 1)
        return id, r
    end
end

return Group
