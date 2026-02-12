这个仓库使用的底层 sparse-set 核心来自 [https://github.com/ushen-pyj/lua-sparse-set](https://github.com/ushen-pyj/lua-sparse-set)

**注意：**
- 需要自行进入 `lua-sparse-set` 仓库并编译对应的 C 库。
- 本仓库组件数据存储在 Lua 侧而非 C 侧，因此不具备 C 语言 ECS 方案中常见的“内存连续性”性能优势。

## 使用示例

```lua
local ecs = require "ecs"

local world = ecs.world()

world:template("pos", { x = 0, y = 0 })
world:template("vel", { dx = 0, dy = 0 })

world:system({"pos", "vel"}, function(dt, id, pos, vel)
    pos.x = pos.x + vel.dx * dt
    pos.y = pos.y + vel.dy * dt
    print(string.format("Entity %d moved to (%.1f, %.1f)", id, pos.x, pos.y))
end)

local player_id = world:create {
    pos = { x = 10, y = 10 },
    vel = { dx = 5, dy = -2 }
}

world:create {
    pos = true,
    vel = true
}

local view = world:view("pos", "vel")
for id, comps in view:each() do
    local pos, vel = table.unpack(comps)
    --- do something
end

local dt = 0.016
world:update(dt)

world:destroy(player_id)
```
