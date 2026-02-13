package.cpath = package.cpath .. ";./luaclib/?.so"
local ecs = require "ecs"

local world = ecs.world()

world:template("pos", { x = 0, y = 0 })
world:template("vel", { dx = 0, dy = 0 })
world:template("health", { current = 100, max = 100 })
world:template("faction", { side = "neutral" }) -- side: "hero", "enemy"
world:template("patrol", { range = 10, timer = 0 })

local physics_group = world:group("pos", "vel")
local combat_group = world:group({"faction", "health"}, {"pos"})

local function run_physics(dt)
    for id, pos, vel in physics_group:each() do
        pos.x = pos.x + vel.dx * dt
        pos.y = pos.y + vel.dy * dt
    end
end

--- AI patrol system
world:system({"vel", "patrol"}, function(dt, id, vel, patrol)
    patrol.timer = patrol.timer - dt
    if patrol.timer <= 0 then
        vel.dx = math.random(-2, 2)
        vel.dy = math.random(-2, 2)
        patrol.timer = 2.0
        print(string.format("[AI] Entity %d changed patrol direction", id))
    end
end)

--- combat system
world:system({"pos", "faction", "health"}, function(dt, id, pos, faction, health)
    if faction.side == "hero" then
        for target_id, t_faction, t_health, t_pos in combat_group:each() do
            if t_faction.side == "enemy" then
                local dx = pos.x - t_pos.x
                local dy = pos.y - t_pos.y
                local dist_sq = dx*dx + dy*dy
                
                if dist_sq < 2.0 then
                    t_health.current = t_health.current - 20 * dt
                    print(string.format("[Combat] Hero attacking Enemy %d! HP: %.1f", target_id, t_health.current))
                end
            end
        end
    end
end)

--- death system
local function death_reaper(world)
    local dead_pool = {}
    for id, health in world:view("health"):each() do
        if health.current <= 0 then
            table.insert(dead_pool, id)
        end
    end
    for _, id in ipairs(dead_pool) do
        print(string.format("[Death] Entity %d has been slain!", id))
        world:destroy(id)
    end
end

local player = world:proxy(world:create {
    name = "Player",
    pos = { x = 0, y = 0 },
    vel = { dx = 1, dy = 1 },
    health = { current = 100, max = 100 },
    faction = { side = "hero" }
})

for i = 1, 3 do
    world:create {
        pos = { x = math.random(2, 5), y = math.random(2, 5) },
        vel = true,
        health = { current = 30, max = 30 },
        faction = { side = "enemy" },
        patrol = true
    }
end

print("\n--- Starting Game Scene Simulation ---\n")
print(string.format("[Info] Physics Group size: %d", physics_group.size))

-- Demonstrate dynamic group membership
print("[Info] Creating a static object (pos but no vel)...")
local static_obj = world:create({ pos = { x = 100, y = 100 } })
print(string.format("[Info] Physics Group size remains: %d", physics_group.size))

print("[Info] Adding velocity to the static object...")
world:add(static_obj, "vel", { dx = -1, dy = -1 })
print(string.format("[Info] Physics Group size updated: %d", physics_group.size))

print("[Info] Removing velocity from the object...")
world:remove(static_obj, "vel")
print(string.format("[Info] Physics Group size decreased: %d", physics_group.size))

for frame = 1, 10 do
    local dt = 0.5 
    print(string.format("\n--- Frame %d ---", frame))
    
    run_physics(dt)
    world:update(dt)
    
    death_reaper(world)
    
    if world:valid(player._id) then
        print(string.format("[World] Player Pos: (%.1f, %.1f) | HP: %.1f", 
            player.pos.x, player.pos.y, player.health.current))
    end
end

print("\n--- Simulation Finished ---")
