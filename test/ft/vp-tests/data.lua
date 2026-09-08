--- A boat and an aircraft to drive, shaped like the ones the popular mods ship.
---
--- Taken from what those mods actually declare, read out of a running game rather than
--- guessed at: Cargo Ships' indep-boat and AAI's ironclad collide with ground_tile and
--- nothing else that matters, so they can only be on water; the eight planes in Aircraft
--- and the four craft in Hovercrafts collide with nothing at all. Both are otherwise
--- ordinary cars, which is what every one of those mods builds on.
local function vehicle(name, layers)
    local prototype = table.deepcopy(data.raw.car.car)
    prototype.name = name
    prototype.minable = { mining_time = 0.1, result = "car" }
    prototype.collision_mask = { layers = layers }
    return prototype
end

data:extend{
    vehicle("vp-tests-boat", { ground_tile = true }),
    vehicle("vp-tests-plane", {}),
}
