require "test.bootstrap"

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
    for id, p, v in view:each() do
        count = count + 1
        results[id] = {p, v}
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

local function test_group_partial()
    print("Testing Partial Ownership Group...")
    local world = ecs.world()
    
    -- gA owns vel, filters pos
    local gA = world:group({"vel"}, {"pos"})
    -- gB owns accel, filters pos
    local gB = world:group({"accel"}, {"pos"})
    
    local e1 = world:create({ pos = "p1", vel = "v1", accel = "a1" })
    local e2 = world:create({ pos = "p2", vel = "v2" })
    local e3 = world:create({ pos = "p3", accel = "a3" })
    
    assert_eq(gA.size, 2, "gA size should be 2")
    assert_eq(gB.size, 2, "gB size should be 2")
    
    -- Test iteration gA
    local count = 0
    for id, comps in gA:iter() do
        count = count + 1
        if id == e1 then
            assert_eq(comps[1], "v1") -- vel (owned)
            assert_eq(comps[2], "p1") -- pos (filtered)
        end
    end
    assert_eq(count, 2)
    
    -- Test iteration gB
    count = 0
    for id, comps in gB:iter() do
        count = count + 1
        if id == e1 then
            assert_eq(comps[1], "a1") -- accel (owned)
            assert_eq(comps[2], "p1") -- pos (filtered)
        end
    end
    assert_eq(count, 2)
    
    print("Partial Ownership Group tests passed.")
end

local function test_group_conflict()
    print("Testing Group Ownership Conflict...")
    local world = ecs.world()
    
    world:group("pos", "vel")
    
    -- Should fail to create another group that owns 'pos'
    local ok, err = pcall(function()
        world:group("pos", "accel")
    end)
    
    assert_false(ok, "Should not allow duplicate ownership of 'pos'")
    assert_true(err:match("Group conflict"), "Error message should mention conflict")
    
    -- Should ALLOW partial group that only FILTERS 'pos'
    local ok2 = pcall(function()
        world:group({"accel"}, {"pos"})
    end)
    assert_true(ok2, "Should allow filtering a component owned by another group")
    
    print("Group Ownership Conflict tests passed.")
end

local function test_nested_groups()
    print("Testing Nested Groups...")
    local world = ecs.world()
    
    -- G1 (General): pos, vel
    local G1 = world:group("pos", "vel")
    -- G2 (Specific): pos, vel, combat (Subgroup of G1)
    local G2 = world:group("pos", "vel", "combat")
    
    local e1 = world:create({pos=1, vel=1})          -- Only G1
    local e2 = world:create({pos=2, vel=2, combat=1}) -- G1 and G2
    local e3 = world:create({pos=3})                -- Neither
    
    -- Check initial state
    assert_eq(G1.size, 2, "G1 size should be 2")
    assert_eq(G2.size, 1, "G2 size should be 1")
    
    -- Check Memory Layout (Specific groups come first)
    local set_pos = world.component_sets["pos"]
    assert_eq(set_pos:at(1), e2, "Entity e2 (Specific) should be at pos 1")
    assert_eq(set_pos:at(2), e1, "Entity e1 (General) should be at pos 2")
    
    -- Check Iteration Results and Order for G1 (General)
    print("  - Verifying iteration order for G1 (General)...")
    local results = {}
    for id, p, v in G1:each() do
        table.insert(results, {id = id, p = p, v = v})
    end
    assert_eq(#results, 2, "G1 should have 2 entities")
    assert_eq(results[1].id, e2, "First in G1 iteration should be e2 (most specific)")
    assert_eq(results[2].id, e1, "Second in G1 iteration should be e1")
    assert_eq(results[1].p, 2, "e2 data check")
    assert_eq(results[2].p, 1, "e1 data check")

    -- Add combat to e1 -> moves it into G2
    print("  - Adding combat to e1...")
    world:add(e1, "combat", 1)
    assert_eq(G1.size, 2, "G1 size remains 2")
    assert_eq(G2.size, 2, "G2 size increased to 2")
    
    -- Now both are in G2, order depends on which was moved last but both are in G2 section
    for id, p, v, c in G2:each() do
        assert_true(id == e1 or id == e2)
    end

    -- Remove combat from e1 -> moves it out of G2 but stays in G1
    print("  - Removing combat from e1...")
    world:remove(e1, "combat")
    assert_eq(G1.size, 2)
    assert_eq(G2.size, 1)
    assert_eq(G2:at(1), e2, "e2 should still be at index 1 of G2")
    
    print("Nested Groups tests passed.")
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
    world:add(e1, "c_pos", {x = 1.5, y = 2.5, active = true})
    
    local cp = world:get(e1, "c_pos")
    assert_eq(cp.x, 1.5)
    assert_eq(cp.y, 2.5)
    assert_eq(cp.active, true)
    
    -- Update C component
    cp.x = 10.5
    assert_eq(cp.x, 10.5)
    
    -- Use in view
    local view = world:view("c_pos")
    local count = 0
    for id, cp_val in view:each() do
        count = count + 1
        assert_eq(cp_val.x, 10.5)
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
    for id, pos in view:each() do
        results[#results+1] = pos.x
    end
    
    table.sort(results)
    assert_eq(results[1], 1.0)
    assert_eq(results[2], 7.0)
    
    print("Systems tests passed.")
end

local function test_view_cache_recovers_after_component_registration()
    print("Testing View Cache Recovery...")
    local world = ecs.world()

    local view = world:view("pos")
    local id = world:create({ pos = { x = 42 } })

    local count = 0
    local found = false
    for eid, pos in view:each() do
        count = count + 1
        if eid == id and pos.x == 42 then
            found = true
        end
    end

    assert_eq(count, 1, "View should recover after component registration")
    assert_true(found, "View should return the newly created entity")
    print("View Cache Recovery tests passed.")
end

local function test_destroy_signal_on_entity_destroy()
    print("Testing Destroy Signal on Entity Destroy...")
    local world = ecs.world()

    local called = 0
    world:on_destroy("pos", function()
        called = called + 1
    end)

    local id = world:create({ pos = { x = 1 }, vel = { x = 2 } })
    world:destroy(id)

    assert_eq(called, 1, "Destroy signal should be triggered when destroying an entity")
    print("Destroy Signal tests passed.")
end

local function test_template_deep_copy()
    print("Testing Template Deep Copy...")
    local world = ecs.world()
    world:template("enemy", { stats = { hp = 100, mp = 50 } })

    local e1 = world:create({ enemy = true })
    local e2 = world:create({ enemy = true })

    world:get(e1, "enemy").stats.hp = 1
    assert_eq(world:get(e2, "enemy").stats.hp, 100, "Template nested fields should not be shared")
    print("Template Deep Copy tests passed.")
end

local function test_group_owned_filter_role_distinction()
    print("Testing Group Owned/Filter Role Distinction...")
    local world = ecs.world()

    local g1 = world:group({ "A" }, { "B" })
    local g2 = world:group({ "B" }, { "A" })
    assert_true(g1 ~= g2, "Groups with swapped owned/filter roles should be distinct")

    local e1 = world:create({ A = 1, B = 1 })
    local e2 = world:create({ A = 2 })
    local e3 = world:create({ B = 3 })

    assert_eq(g1.size, 1, "g1 should include only entities with A and B")
    assert_eq(g2.size, 1, "g2 should include only entities with B and A")

    local count1, count2 = 0, 0
    for id in g1:each() do
        count1 = count1 + 1
        assert_eq(id, e1, "g1 should only return the AB entity")
    end
    for id in g2:each() do
        count2 = count2 + 1
        assert_eq(id, e1, "g2 should only return the AB entity")
    end
    assert_eq(count1, 1)
    assert_eq(count2, 1)
    assert_true(world:valid(e2))
    assert_true(world:valid(e3))
    print("Group Owned/Filter Role Distinction tests passed.")
end

local function test_group_owned_filter_overlap_rejected()
    print("Testing Group Owned/Filter Overlap Rejection...")
    local world = ecs.world()
    local ok, err = pcall(function()
        world:group({ "A" }, { "A" })
    end)
    assert_false(ok, "Group creation should fail when a component is both owned and filtered")
    assert_true(err:match("cannot be both owned and filtered") ~= nil, "Error should mention owned/filter overlap")
    print("Group Owned/Filter Overlap Rejection tests passed.")
end

local function run_tests()
    test_world_basic()
    test_entity_proxy()
    test_view()
    test_group()
    test_late_group()
    test_group_partial()
    test_group_conflict()
    test_nested_groups()
    test_c_components()
    test_templates()
    test_systems()
    test_view_cache_recovers_after_component_registration()
    test_destroy_signal_on_entity_destroy()
    test_template_deep_copy()
    test_group_owned_filter_role_distinction()
    test_group_owned_filter_overlap_rejected()
    print("\nALL ECS TESTS PASSED")
end

run_tests()
