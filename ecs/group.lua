
local Group = {}
Group.__index = Group

function Group.new(world, components)
    local self = setmetatable({}, Group)
    self.world = world
    self.components = components
    self.size = 0
    
    -- Cache the component sets for faster access
    self.sets = {}
    for _, name in ipairs(components) do
        self.sets[name] = world:register_component(name)
    end
    
    self:initialize()
    
    return self
end

function Group:initialize()
    local leader_set = self.sets[self.components[1]]
    -- We assume the leader set is the smallest or most restrictive set for now
    -- Or just use one set to drive the scan.
    local count = leader_set:size()
    
    -- We iterate from 1 to count
    -- Whenever we find a match, we swap it to position (self.size + 1)
    -- This accumulates all matches at the beginning [1, self.size]
    
    local i = 1
    while i <= count do
        -- When we swap logic:
        -- If current 'i' matches, we swap it to 'target_pos' and inc 'target_pos'.
        -- But wait, if we swap, what comes into 'i'? 
        -- If 'i > target_pos', we bring an un-checked entity? Usually yes.
        -- But here, 'target_pos' grows from 1. 
        -- So 'target_pos' is always <= 'i'.
        -- The entity at 'target_pos' (the one being swapped out) has naturally *already been processed*.
        -- Wait. If target_pos < i, then yes.
        -- If we swap, we are putting a matched entity safely into the 'done' pile.
        -- And we pull a garbage/non-matched entity out to 'i'.
        -- Does 'i' need to be re-checked? 
        -- No, because we are scanning 'i'. The entity we just pulled from 'target_pos' was ALREADY scanned when we were at 'target_pos' (earlier).
        -- So it is safe to proceed.
        
        local id = leader_set:at(i)
        
        if self:match(id) then
            local target_pos = self.size + 1
            if i ~= target_pos then
                for _, set in pairs(self.sets) do
                    local current_pos = set:index_of(id) 
                    -- index_of returns 1-based index from Lua binding
                    if current_pos then
                        set:swap(current_pos, target_pos)
                    end
                end
            end
            self.size = self.size + 1
        end
        i = i + 1
    end
end

function Group:owns(component_name)
    for _, name in ipairs(self.components) do
        if name == component_name then return true end
    end
    return false
end

function Group:match(id)
    for _, set in pairs(self.sets) do
        if not set:contains(id) then return false end
    end
    return true
end

function Group:on_add(id, component_name)
    if not self:owns(component_name) then return end
    
    -- Check if the entity now has all components required by the group
    if self:match(id) then
        self:add_to_group(id)
    end
end

function Group:on_remove(id, component_name)
    if not self:owns(component_name) then return end
    
    -- If it was in the group (implied by currently having all components before removal, 
    -- but here we are called AFTER removal if we hook into remove, or BEFORE? 
    -- Usually better to hook before removal or handle the state change carefully.
    -- Let's assume we handle this by checking if it WAS in the group.
    -- Simplified: ensure it is moved out of the group range.
    
    -- Check if it is currently inside the group range
    -- We assume the group property holds if index <= size
    -- We need to check if the entity WAS in the group.
    -- Since this is called BEFORE actual removal from the set (in World:remove),
    -- the entity still has the component. 
    -- If we rely on match(id), it will return true because the component is still there.
    -- However, we need to know if it is within the 'group region' of the dense array.
    
    if self:is_in_group(id) then
        self:remove_from_group(id)
    end
end

function Group:is_in_group(id)
    -- Check if the entity is in the valid group range [1, size] for all sets
    -- Just checking one set is enough if invariant holds
    local leader_set = self.sets[self.components[1]]
    local pos = leader_set:index_of(id)
    return pos and pos <= self.size
end

function Group:add_to_group(id)
    local target_pos = self.size + 1
    for _, set in pairs(self.sets) do
        local current_pos = set:index_of(id)
        if current_pos then -- Should be there
             -- indices are 1-based in Lua, swap expects 1-based
            set:swap(current_pos, target_pos)
        end
    end
    self.size = self.size + 1
end

function Group:remove_from_group(id)
    local target_pos = self.size
    for _, set in pairs(self.sets) do
        local current_pos = set:index_of(id)
        if current_pos then 
            set:swap(current_pos, target_pos)
        end
    end
    self.size = self.size - 1
end

local CComponent = require "ecs.c_component"

function Group:iter()
    -- Iterator that goes from 1 to self.size
    local size = self.size
    if size == 0 then return function() end end

    local world = self.world
    -- Cache sets in indexed order matching self.components
    local sets = {}
    local names = self.components
    for i, name in ipairs(names) do
        sets[i] = self.sets[name]
    end
    
    local results = {}
    local n_sets = #sets
    
    -- Use the first set as the leader
    -- checking leader iterator
    local iter_func, state, var = sets[1]:iter()

    return function()
        -- Ensure we don't go beyond group size
        -- var is the previous index (integer). Initial 0.
        if var >= size then return nil end
        
        local idx, id, data = iter_func(state, var)
        -- idx matches var + 1
        var = idx
        
        for i = 1, n_sets do
            local d
            if i == 1 then
                d = data
            else
                local _, val = sets[i]:at(idx)
                d = val
            end
            
            local desc = world.c_descriptors[names[i]]
            if desc then
                results[i] = CComponent.new(world, id, names[i], desc)
            else
                results[i] = d
            end
        end
        
        return id, results
    end
end

return Group
