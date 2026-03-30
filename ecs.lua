local world_class = require "ecs.world"

local ecs = {}

function ecs.world()
    return world_class.new()
end

return ecs
