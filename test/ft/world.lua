--- A patch of ground to drive on, and the wheel.
---
--- Each test claims its own square of nauvis, paves it with whatever surface it wants to
--- test on, and gets a fuelled car with the player already in it. Driving is done by
--- writing riding_state, which is what a keypress does: no synthetic input is involved
--- anywhere, and the physics cannot tell the difference.
local world = {}

local PATCH = 96
local COLUMNS = 6
--- Well clear of the spawn point. Freeplay puts the crashed ship there, and a vehicle
--- placed next to wreckage is a vehicle you cannot pull away from cleanly.
local ORIGIN = 400

local prepared = false
local patch_index = -1

--- What the player is holding down. riding_state is the *current* input, so the game
--- clears it again the moment nothing is pressing it -- exactly as a key does. Holding a
--- control therefore means writing it every tick, which is what this does.
---
--- on_nth_tick rather than on_event: the mod itself owns on_tick, and registering a
--- second handler for the same event would replace the mod's own and quietly turn the
--- physics off underneath the test.
script.on_nth_tick(1, function()
    local player = game.players[1]
    if world.controls and player and player.driving then
        player.riding_state = world.controls
    end
end)

local function prepare()
    if prepared then return end
    local surface = game.surfaces["nauvis"]
    local span = COLUMNS * PATCH
    surface.request_to_generate_chunks({ x = ORIGIN + span / 2, y = ORIGIN + span / 2 },
                                       math.ceil(span / 32) + 1)
    surface.force_generate_chunk_requests()
    world.surface = surface
    prepared = true
end

--- @param tile string what to pave the patch with
function world.patch(tile)
    prepare()
    patch_index = patch_index + 1
    local left = ORIGIN + (patch_index % COLUMNS) * PATCH
    local top = ORIGIN + math.floor(patch_index / COLUMNS) * PATCH
    local surface = world.surface
    local player = game.players[1]

    -- out of whatever the last test left them sitting in, or the new car never gets a
    -- driver and the mod never hears about it
    world.controls = nil
    if player.driving then player.driving = false end

    local area = { { left, top }, { left + PATCH, top + PATCH } }
    for _, entity in pairs(surface.find_entities(area)) do
        if entity.valid and entity.type ~= "character" then entity.destroy() end
    end

    if tile then
        local tiles = {}
        for x = left, left + PATCH - 1 do
            for y = top, top + PATCH - 1 do
                tiles[#tiles + 1] = { name = tile, position = { x, y } }
            end
        end
        surface.set_tiles(tiles)
    end

    local patch = { surface = surface, player = player, left = left, top = top,
                    area = area, centre = { x = left + PATCH / 2, y = top + PATCH / 2 } }

    --- A car in the middle of the patch, fuelled, with the player at the wheel.
    ---@param name string? defaults to a car
    function patch.drive(name)
        local car = surface.create_entity{ name = name or "car", position = patch.centre,
                                           force = "player" }
        assert(car, "could not place a " .. (name or "car"))
        car.insert{ name = "nuclear-fuel", count = 1 }
        -- nothing within reach to hit, so pulling away is the same every run. The patch
        -- is cleared when it is claimed, but a vehicle nose to nose with wreckage is
        -- exactly the thing that makes a start awkward, so it is worth checking.
        local obstructions = {}
        for _, other in pairs(surface.find_entities{
            { patch.centre.x - 8, patch.centre.y - 8 },
            { patch.centre.x + 8, patch.centre.y + 8 } })
        do
            if other.valid and other ~= car and other.type ~= "character" then
                obstructions[#obstructions + 1] = other.name
            end
        end
        assert.same({}, obstructions, "something is parked next to the car")
        player.teleport(patch.centre, surface)
        player.driving = true
        assert(player.vehicle, "the player did not get into the vehicle")
        patch.car = car
        return car
    end

    --- Hold the controls. Exactly what a key held down does.
    ---@param acceleration defines.riding.acceleration
    ---@param direction defines.riding.direction?
    function patch.hold(acceleration, direction)
        world.controls = {
            acceleration = acceleration,
            direction = direction or defines.riding.direction.straight,
        }
        player.riding_state = world.controls
    end

    --- Let go of everything
    function patch.release()
        world.controls = nil
        player.riding_state = {
            acceleration = defines.riding.acceleration.nothing,
            direction = defines.riding.direction.straight,
        }
    end

    --- Everything of one name lying about in the patch
    function patch.count(name)
        return surface.count_entities_filtered{ area = area, name = name }
    end

    return patch
end

--- A big flat square of one surface, made once and reused. The measurement fixtures drive
--- for hundreds of tiles, which no ordinary patch is large enough to hold, and painting a
--- fresh one per trial would cost more than the measuring does.
local arenas = {}
local ARENA = 420

---@param tile string
function world.arena(tile)
    prepare()
    if arenas[tile] then
        local arena = arenas[tile]
        for _, entity in pairs(world.surface.find_entities(arena.area)) do
            if entity.valid and entity.type ~= "character" then entity.destroy() end
        end
        return arena
    end

    local index = 0
    for _ in pairs(arenas) do index = index + 1 end
    local left, top = 3000 + index * (ARENA + 100), 3000
    local surface = world.surface
    surface.request_to_generate_chunks({ x = left + ARENA / 2, y = top + ARENA / 2 },
                                       math.ceil(ARENA / 32) + 2)
    surface.force_generate_chunk_requests()

    local tiles = {}
    for x = left, left + ARENA - 1 do
        for y = top, top + ARENA - 1 do
            tiles[#tiles + 1] = { name = tile, position = { x, y } }
        end
    end
    surface.set_tiles(tiles)

    arenas[tile] = {
        surface = surface,
        centre = { x = left + ARENA / 2, y = top + ARENA / 2 },
        area = { { left, top }, { left + ARENA, top + ARENA } },
    }
    return arenas[tile]
end

--- Put a fuelled vehicle in the middle of an arena with the player at the wheel
---@param arena table
---@param name string
function world.launch(arena, name)
    local player = game.players[1]
    world.controls = nil
    -- Getting out is not always possible: stepping out of a boat means stepping onto
    -- water, which the game refuses, and the player stays aboard. Whatever they were in
    -- is a test vehicle and disposable, so it goes.
    if player.driving then
        local previous = player.vehicle
        player.driving = false
        if player.driving and previous and previous.valid then previous.destroy() end
    end
    local car = arena.surface.create_entity{ name = name, position = arena.centre,
                                             force = "player" }
    assert(car, "could not place a " .. name)
    car.insert{ name = "nuclear-fuel", count = 1 }
    car.orientation = 0
    player.teleport(arena.centre, arena.surface)
    player.driving = true
    assert.equals(name, player.vehicle and player.vehicle.name,
        "the player ended up in the wrong vehicle, or none")
    return car
end

--- Hold the controls, as patch.hold does
function world.hold(acceleration, direction)
    world.controls = { acceleration = acceleration,
                       direction = direction or defines.riding.direction.straight }
    game.players[1].riding_state = world.controls
end

--- The mod's own record of a car, or nil if it is not tracking it
---@param car LuaEntity
function world.tracked(car)
    return storage.cars[car.unit_number]
end

---@param car LuaEntity
function world.tracked_tank(car)
    return storage.tanks[car.unit_number]
end

return world
