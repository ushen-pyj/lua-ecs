package.path = package.path .. ";./?.lua;./ecs/?.lua"
package.cpath = package.cpath .. ";../lua-sparse-set/build/?.so"

local ecs = require "ecs"

local function assert_eq(a, b, msg)
    if a ~= b then
        error(string.format("%s: expected %s, got %s", msg or "Assertion failed", tostring(b), tostring(a)))
    end
end

local function assert_true(a, msg)
    if not a then
        error(string.format("%s: expected true, got %s", msg or "Assertion failed", tostring(a)))
    end
end

local function assert_false(a, msg)
    if a then
        error(string.format("%s: expected false, got %s", msg or "Assertion failed", tostring(a)))
    end
end

local function test_world_basic()
    print("Testing World Basic...")
    local world = ecs.world()
    
    -- Create entity
    local e1 = world:create()
    assert_true(world:valid(e1), "e1 should be valid")
    
    -- Add Lua component
    world:add(e1, "pos", {x = 10, y = 20})
    assert_true(world:has(e1, "pos"), "e1 should have pos")
    local pos = world:get(e1, "pos")
    assert_eq(pos.x, 10)
    assert_eq(pos.y, 20)
    
    -- Remove component
    world:remove(e1, "pos")
    assert_false(world:has(e1, "pos"), "e1 should not have pos after removal")
    assert_eq(world:get(e1, "pos"), nil)
    
    -- Destroy entity
    world:destroy(e1)
    assert_false(world:valid(e1), "e1 should be invalid after destruction")
    
    print("World Basic tests passed.")
end

local function test_entity_proxy()
    print("Testing Entity Proxy...")
    local world = ecs.world()
    local e1_id = world:create()
    local e1 = world:proxy(e1_id)
    
    -- Set via proxy
    e1.pos = {x = 1, y = 2}
    assert_true(e1:has("pos"))
    assert_eq(e1.pos.x, 1)
    
    -- Update via proxy
    e1.pos = {x = 3, y = 4}
    assert_eq(e1.pos.x, 3)
    
    -- Remove via proxy
    e1.pos = nil
    assert_false(e1:has("pos"))
    
    -- Destroy via proxy
    e1:destroy()
    assert_false(world:valid(e1_id))
    
    print("Entity Proxy tests passed.")
end

local function test_view()
    print("Testing View...")
    local world = ecs.world()
    
    local e1 = world:create({pos = {x=1}, vel = {x=2}})
    local e2 = world:create({pos = {x=3}})
    local e3 = world:create({vel = {x=4}})
    local e4 = world:create({pos = {x=5}, vel = {x=6}, accel = {x=7}})
    
    -- View for pos and vel
    local view = world:view("pos", "vel")
    local count = 0
    local results = {}
    for id, comps in view:each() do
        count = count + 1
        results[id] = {comps[1], comps[2]}
    end
    
    assert_eq(count, 2, "View should find 2 entities")
    assert_true(results[e1] ~= nil)
    assert_true(results[e4] ~= nil)
    assert_eq(results[e1][1].x, 1)
    assert_eq(results[e1][2].x, 2)
    
    print("View tests passed.")
end

local function test_group()
    print("Testing Group...")
    local world = ecs.world()
    
    -- Pre-register group
    local group = world:group("pos", "vel")
    
    local e1 = world:create({pos = {x=1}, vel = {x=2}})
    local e2 = world:create({pos = {x=3}}) -- not in group
    local e3 = world:create({pos = {x=4}, vel = {x=5}})
    
    assert_eq(group.size, 2, "Group size should be 2")
    
    -- Test iteration
    local count = 0
    for id, comps in group:iter() do
        count = count + 1
    end
    assert_eq(count, 2)
    
    -- Add to group after creation
    world:add(e2, "vel", {x=6})
    assert_eq(group.size, 3, "Group size should be 3 after adding component")
    
    -- Remove from group
    world:remove(e1, "pos")
    assert_eq(group.size, 2, "Group size should be 2 after removing component")
    
    -- Destroy entity in group
    world:destroy(e3)
    assert_eq(group.size, 1, "Group size should be 1 after destroying entity")
    
    print("Group tests passed.")
end

local function test_late_group()
    print("Testing Late Group Registration...")
    local world = ecs.world()
    
    local e1 = world:create({pos = {x=1}, vel = {x=2}})
    local e2 = world:create({pos = {x=3}, vel = {x=4}})
    local e3 = world:create({pos = {x=5}}) -- not in group
    
    -- Register group AFTER entities exist
    local group = world:group("pos", "vel")
    
    assert_eq(group.size, 2, "Late group should find existing entities")
    
    print("Late Group Registration tests passed.")
end

local function test_c_components()
    print("Testing C Components...")
    local world = ecs.world()
    
    -- Register C component
    world:register({
        name = "c_pos",
        "x:float",
        "y:float",
        "active:bool"
    })
    
    local e1 = world:create()
    world:add(e1, "c_pos", {x = 1.5, y = 2.5, active = 1})
    
    local cp = world:get(e1, "c_pos")
    assert_eq(cp.x, 1.5)
    assert_eq(cp.y, 2.5)
    assert_eq(cp.active, 1)
    
    -- Update C component
    cp.x = 10.5
    assert_eq(cp.x, 10.5)
    
    -- Use in view
    local view = world:view("c_pos")
    local count = 0
    for id, comps in view:each() do
        count = count + 1
        assert_eq(comps[1].x, 10.5)
    end
    assert_eq(count, 1)
    
    print("C Components tests passed.")
end

local function test_templates()
    print("Testing Templates...")
    local world = ecs.world()
    
    world:template("enemy", {hp = 100, mp = 50})
    
    local e1 = world:create({enemy = true})
    local enemy = world:get(e1, "enemy")
    assert_eq(enemy.hp, 100)
    assert_eq(enemy.mp, 50)
    
    -- Ensure it's a copy
    enemy.hp = 80
    local e2 = world:create({enemy = true})
    assert_eq(world:get(e2, "enemy").hp, 100)
    
    print("Templates tests passed.")
end

local function test_systems()
    print("Testing Systems...")
    local world = ecs.world()
    
    world:create({pos = {x=0}, vel = {x=10}})
    world:create({pos = {x=5}, vel = {x=20}})
    
    world:system({"pos", "vel"}, function(dt, id, pos, vel)
        pos.x = pos.x + vel.x * dt
    end)
    
    world:update(0.1)
    
    local view = world:view("pos")
    local results = {}
    for id, comps in view:each() do
        results[#results+1] = comps[1].x
    end
    
    table.sort(results)
    assert_eq(results[1], 1.0)
    assert_eq(results[2], 7.0)
    
    print("Systems tests passed.")
end

local function run_tests()
    test_world_basic()
    test_entity_proxy()
    test_view()
    test_group()
    test_late_group()
    test_c_components()
    test_templates()
    test_systems()
    print("\nALL ECS TESTS PASSED")
end

run_tests()
