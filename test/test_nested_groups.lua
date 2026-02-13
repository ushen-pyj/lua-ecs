
package.path = package.path .. ";./?.lua;./ecs/?.lua"
package.cpath = package.cpath .. ";./luaclib/?.so;;"

local ecs = require "ecs"

local function assert_eq(a, b, msg)
    if a ~= b then
        error(string.format("%s: expected %s, got %s", msg or "Assertion failed", tostring(b), tostring(a)))
    end
end

local function test_nested_groups()
    print("Testing Nested Groups...")
    local world = ecs.world()
    
    -- G1 owns A, B
    local G2 = world:group("A", "B")
    -- G2 owns A, B, C (Should be nested subgroup of G1)
    local G1 = world:group("A", "B", "C")
    
    local e1 = world:create({A=1, B=1})       -- Should be in G2 only
    local e2 = world:create({A=1, B=1, C=1}) -- Should be in G1 and G2
    local e3 = world:create({A=1})           -- Should be in neither
    
    -- Check initial state
    -- Expected memory for set A, B: [ e2 (G1) | e1 (G2) | e3(...) ]
    -- G1 size = 1, G2 size = 2
    assert_eq(G1.size, 1, "G1 size should be 1")
    assert_eq(G2.size, 2, "G2 size should be 2")
    
    local setA = world.component_sets["A"]
    assert_eq(setA:at(1), e2, "Entity at pos 1 should be e2 (G1)")
    assert_eq(setA:at(2), e1, "Entity at pos 2 should be e1 (G2)")
    
    print("  - Initial state OK")
    
    -- Add C to e1
    print("  - Adding C to e1...")
    world:add(e1, "C", 1)
    -- Now: [ e1, e2 | ... ] or [ e2, e1 | ... ]
    -- Both e1 and e2 should be in G1 (size 2) and G2 (size 2)
    assert_eq(G1.size, 2, "G1 size should be 2 after adding C to e1")
    assert_eq(G2.size, 2, "G2 size should be 2")
    
    -- Remove C from e2
    print("  - Removing C from e2...")
    world:remove(e2, "C")
    -- Now: e1 is in G1, e2 is in G2 only
    -- G1 size = 1, G2 size = 2
    assert_eq(G1.size, 1, "G1 size should be 1 after removing C from e2")
    assert_eq(G2.size, 2, "G2 size should stay 2")
    
    -- Verify positions in sparse set
    local pos_e1 = setA:index_of(e1)
    local pos_e2 = setA:index_of(e2)
    assert_eq(pos_e1 <= G1.size, true, "e1 should be in G1 section")
    assert_eq(pos_e2 > G1.size and pos_e2 <= G2.size, true, "e2 should be in G2-only section")

    -- Verify iteration results and order
    print("  - Verifying iteration order for G2 (AB)...")
    -- G1 owns (A,B,C), size 1 (e1)
    -- G2 owns (A,B), size 2 (e1, e2)
    -- Layout should be: [e1, e2] because e1 is in a more specific group
    local results = {}
    for id, a, b in G2:each() do
        table.insert(results, {id = id, a = a, b = b})
    end
    
    assert_eq(#results, 2, "G2:each() should return 2 entities")
    assert_eq(results[1].id, e1, "First entity in G2 should be e1 (since it's in G1)")
    assert_eq(results[2].id, e2, "Second entity in G2 should be e2")
    assert_eq(results[1].a, 1, "e1 partial data A check")
    
    print("  - Verifying iteration order for G1 (ABC)...")
    results = {}
    for id, a, b, c in G1:each() do
        table.insert(results, {id = id, a = a, b = b, c = c})
    end
    assert_eq(#results, 1, "G1:each() should return 1 entity")
    assert_eq(results[1].id, e1, "Entity in G1 should be e1")
    assert_eq(results[1].c, 1, "e1 partial data C check")

    print("Nested Groups test passed!")
end

test_nested_groups()
