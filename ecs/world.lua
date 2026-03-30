local sparseset = require "sparseset"
local create_proxy = require "ecs.entity"
local View = require "ecs.view"
local Group = require "ecs.group"

local World = {}
World.__index = World

local CComponent = require "ecs.c_component"

local C_TYPES = {
    int = { id = 1, size = 4, pack = "i4" },
    float = { id = 2, size = 4, pack = "f" },
    double = { id = 3, size = 8, pack = "d" },
    byte = { id = 4, size = 1, pack = "I1" },
    bool = { id = 5, size = 1, pack = "I1" },
}

local function deep_copy(value, seen)
    if type(value) ~= "table" then
        return value
    end
    seen = seen or {}
    if seen[value] then
        return seen[value]
    end

    local copy = {}
    seen[value] = copy
    for k, v in pairs(value) do
        copy[deep_copy(k, seen)] = deep_copy(v, seen)
    end
    return setmetatable(copy, getmetatable(value))
end

local function contains(list, value)
    for _, v in ipairs(list) do
        if v == value then
            return true
        end
    end
    return false
end

local function make_group_key(owned_names, filter_names)
    local owned = {}
    local filters = {}

    for i, name in ipairs(owned_names) do
        owned[i] = name
    end
    for i, name in ipairs(filter_names) do
        filters[i] = name
    end

    table.sort(owned)
    table.sort(filters)
    return string.format("O:%s|F:%s", table.concat(owned, "&"), table.concat(filters, "&"))
end

function World.new()
    local self = setmetatable({}, World)
    self.registry = sparseset.new_registry()
    self.component_sets = {}
    self.component_names = {}
    self.c_descriptors = {}
    self.templates = {}
    self.systems = {}
    self.groups = {}
    self.group_chains = {} -- component_name -> sorted list of groups owning it
    self.signals = {
        construct = {},
        update = {},
        destroy = {},
    }
    self.view_cache = {}
    return self
end

local runner_cache = {}
local function get_runner(n)
    if runner_cache[n] then return runner_cache[n] end
    
    local args = {"id"}
    local params = {"dt", "view", "fn"}
    for i = 1, n do table.insert(args, "c" .. i) end
    local arg_str = table.concat(args, ", ")
    
    local code = string.format([[
        return function(dt, view, fn)
            for %s in view:each() do
                fn(dt, %s)
            end
        end
    ]], arg_str, arg_str)
    
    local chunk = load(code)
    runner_cache[n] = chunk()
    return runner_cache[n]
end

function World:on_construct(name, callback)
    self.signals.construct[name] = self.signals.construct[name] or {}
    table.insert(self.signals.construct[name], callback)
end

function World:on_update(name, callback)
    self.signals.update[name] = self.signals.update[name] or {}
    table.insert(self.signals.update[name], callback)
end

function World:on_destroy(name, callback)
    self.signals.destroy[name] = self.signals.destroy[name] or {}
    table.insert(self.signals.destroy[name], callback)
end

function World:trigger_signal(type, name, id)
    local callbacks = self.signals[type][name]
    if callbacks then
        for _, cb in ipairs(callbacks) do
            cb(self, id)
        end
    end
end

function World:register(decl)
    if type(decl) == "string" then
        return self:register_component(decl)
    end
    
    local name = decl.name
    if not name then error("Component must have a name") end
    
    if self.component_sets[name] then return self.component_sets[name] end
    local is_c = false
    local fields = {}
    local field_names = {}
    local format = "<"
    local stride = 0
    
    for _, s in ipairs(decl) do
        local fname, ftype = s:match("([%w_]+):([%w_]+)")
        if fname and ftype then
            local info = C_TYPES[ftype]
            if not info then error("Unknown type: "..ftype) end
            is_c = true
            fields[fname] = { offset = stride, type = info.id }
            table.insert(field_names, fname)
            format = format .. info.pack
            stride = stride + info.size
        end
    end
    
    local set
    if is_c then
        set = sparseset.new_set(stride)
        self.c_descriptors[name] = { 
            stride = stride, 
            fields = fields, 
            field_names = field_names, 
            format = format 
        }
    else
        set = sparseset.new_set()
    end
    
    self.component_sets[name] = set
    table.insert(self.component_names, name)
    self.view_cache = {}
    return set
end

function World:register_component(name)
    if self.component_sets[name] then return self.component_sets[name] end
    local set = sparseset.new_set()
    self.component_sets[name] = set
    table.insert(self.component_names, name)
    self.view_cache = {}
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
            self:remove(id, name)
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
        if type(data) == "table" then
            local values = {}
            for i, fname in ipairs(desc.field_names) do
                local v = data[fname]
                if v == nil then
                    v = 0
                elseif type(v) == "boolean" then
                    v = v and 1 or 0
                end
                values[i] = v
            end
            data = string.pack(desc.format, table.unpack(values))
        elseif type(data) ~= "string" then
            data = nil
        end
        
        local is_new = set:insert(id, data)
        if is_new then
             self:update_groups_on_add(id, name)
             self:trigger_signal("construct", name, id)
        else
             self:trigger_signal("update", name, id)
        end
        return self:get(id, name)
    else
        if data == true or data == nil then
            local tpl = self.templates[name]
            if tpl then
                data = deep_copy(tpl)
            else
                data = true
            end
        end
        
        local is_new = set:insert(id, data)
        if is_new then
            self:update_groups_on_add(id, name)
            self:trigger_signal("construct", name, id)
        else
            self:trigger_signal("update", name, id)
        end
        return data
    end
end

function World:replace(id, name, data)
    if not self:has(id, name) then return nil end
    return self:add(id, name, data)
end

function World:patch(id, name, callback)
    local comp = self:get(id, name)
    if not comp then return nil end
    if callback then callback(comp) end
    
    self:trigger_signal("update", name, id)
    return comp
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
    if set and set:contains(id) then 
        self:trigger_signal("destroy", name, id)
        self:update_groups_on_remove(id, name)
        set:remove(id) 
    end
end

function World:proxy(id)
    if not self:valid(id) then return nil end
    return create_proxy(self, id)
end

function World:view(...)
    local names = {...}
    if #names == 0 then return View.new(self, {}) end
    
    local key_names = {}
    for i, n in ipairs(names) do key_names[i] = n end
    table.sort(key_names)
    local key = table.concat(key_names, "|")
    
    if self.view_cache[key] then return self.view_cache[key] end
    
    local view = View.new(self, names)
    if not view.invalid then
        self.view_cache[key] = view
    end
    return view
end

function World:system(names, callback)
    local runner = get_runner(#names)
    table.insert(self.systems, {
        names = names, 
        fn = callback,
        runner = runner
    })
end

function World:group(owned, ...)
    local owned_names = {}
    local filter_names = {}

    if type(owned) == "table" then
        owned_names = owned
        local filter_arg = (...)
        if filter_arg ~= nil and type(filter_arg) ~= "table" then
            error("Group filters must be a table when owned components are passed as a table")
        end
        filter_names = filter_arg or {}
    else
        owned_names = {owned, ...}
    end

    for _, name in ipairs(filter_names) do
        if contains(owned_names, name) then
            error(string.format("Group conflict: component '%s' cannot be both owned and filtered.", name))
        end
    end

    local key = make_group_key(owned_names, filter_names)
    
    if self.groups[key] then return self.groups[key] end

    -- Compatibility check for Nested Groups
    for _, name in ipairs(owned_names) do
        local chain = self.group_chains[name]
        if chain then
            for _, existing in ipairs(chain) do
                -- Check if one is a subset of the other
                local is_subset = true
                for _, ename in ipairs(existing.owned) do
                    local found = false
                    for _, my_name in ipairs(owned_names) do
                        if ename == my_name then found = true; break end
                    end
                    if not found then is_subset = false; break end
                end

                local is_superset = true
                for _, my_name in ipairs(owned_names) do
                    local found = false
                    for _, ename in ipairs(existing.owned) do
                        if my_name == ename then found = true; break end
                    end
                    if not found then is_superset = false; break end
                end

                if not is_subset and not is_superset then
                    error(string.format("Group conflict: Group(%s) and Group(%s) share component '%s' but are not nested.", 
                        key, existing.key, name))
                end
            end
        end
    end
    
    local group = Group.new(self, owned_names, filter_names)
    group.key = key
    
    -- Add to chains and sort by complexity (more components first)
    for _, name in ipairs(owned_names) do
        local chain = self.group_chains[name] or {}
        table.insert(chain, group)
        table.sort(chain, function(a, b) return #a.owned > #b.owned end)
        self.group_chains[name] = chain
    end
    
    self.groups[key] = group
    table.insert(self.groups, group)

    -- Initialize the group for existing entities
    local leader_name = owned_names[1] or filter_names[1]
    local leader_set = self.component_sets[leader_name]
    if leader_set then
        local ids = {}
        local size = leader_set:size()
        for i = 1, size do
            ids[i] = (leader_set:at(i))
        end
        for i = 1, size do
            local id = ids[i]
            if group:match(id) then
                self:update_groups_on_add(id, owned_names[1])
            end
        end
    end

    return group
end

function World:update_groups_on_add(id, name)
    -- 1. Handle non-owned groups
    for _, group in ipairs(self.groups) do
        local is_owned = false
        for _, n in ipairs(group.owned) do
            if n == name then is_owned = true; break end
        end
        if not is_owned then
            group:on_add(id, name)
        end
    end

    local chain = self.group_chains[name]
    if chain then
        -- Process from LEAST specific to MOST specific.
        -- This ensures that supergroups increment their size before subgroups 
        -- "steal" the entity position at the front of the array.
        for i = #chain, 1, -1 do
            local group = chain[i]
            local matches = group:match(id)
            local in_group = group:is_in_group(id)
            if matches and not in_group then
                local target_pos = group.size + 1
                for _, owned_name in ipairs(group.owned) do
                    local set = self.component_sets[owned_name]
                    local current_pos = set:index_of(id)
                    if current_pos then
                        set:swap(current_pos, target_pos)
                    end
                end
                group.size = target_pos
            end
        end
    end
end

function World:update_groups_on_remove(id, name)
    -- Handle non-owned groups
    for _, group in ipairs(self.groups) do
        local is_chained = false
        for _, owned_name in ipairs(group.owned) do
            if owned_name == name then is_chained = true; break end
        end
        if not is_chained then
            group:on_remove(id, name)
        end
    end

    -- Process chain for owned groups (nested sorting)
    local chain = self.group_chains[name]
    if chain then
        for _, group in ipairs(chain) do
            local matches = group:match(id, name)
            local in_group = group:is_in_group(id)
            if in_group and not matches then
                local target_pos = group.size
                for _, owned_name in ipairs(group.owned) do
                    local set = self.component_sets[owned_name]
                    local current_pos = set:index_of(id)
                    if current_pos then
                        set:swap(current_pos, target_pos)
                    end
                end
                group.size = group.size - 1
            end
        end
    end
end

function World:sort(name, comparator)
    local chain = self.group_chains[name]
    if chain then
        -- Sort the most complex group in the chain, it will reorder sub-groups
        chain[1]:sort(comparator)
        return
    end

    local set = self.component_sets[name]
    if not set then return end
    
    local size = set:size()
    if size <= 1 then return end
    
    local ids = {}
    for i = 1, size do
        ids[i] = (set:at(i))
    end
    
    table.sort(ids, function(a, b)
        return comparator(self, a, b)
    end)
    
    for i = 1, size do
        local target_id = ids[i]
        local current_pos = set:index_of(target_id)
        if current_pos ~= i then
            set:swap(current_pos, i)
        end
    end
end

function World:update(dt)
    for _, sys in ipairs(self.systems) do
        local view = self:view(table.unpack(sys.names))
        sys.runner(dt, view, sys.fn)
    end
end

return World
