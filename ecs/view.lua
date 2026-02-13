local View = {}
View.__index = View

function View.new(world, names)
    local self = setmetatable({}, View)
    self.world = world
    self.names = names
    self.n = #names
    
    local sets = {}
    local min_idx = 1
    local min_size = math.huge
    
    for i=1, self.n do
        local set = world.component_sets[names[i]]
        if not set then 
            self.invalid = true
            return self
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
    return self
end

function View:each()
    if self.invalid then return function() end end
    
    local iter_func, state, var = self.sets[self.min_idx]:iter()
    local n = self.n
    local min_idx = self.min_idx
    local sets = self.sets
    
            
    local results = {}
    return function()
        while true do
            local i, id, data = iter_func(state, var)
            if not i then return nil end
            var = i
            local match = true
            for j=1, n do
                if j == min_idx then
                    results[j] = data
                else
                    local d = sets[j]:get(id)
                    if d == nil then
                        match = false
                        break
                    end
                    results[j] = d
                end
            end
            
            if match then
                -- TODO ushen do not update results after return
                return id, results
            end
        end
    end
end

return View
