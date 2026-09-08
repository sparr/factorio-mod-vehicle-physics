--- Verifies where the sandbox actually puts things, so it is never launched on a guess.
local sandbox = require("test.sandbox")
local tracking = require("lib.tracking")
local world = require("test.ft.world")

describe("sandbox placement", function()
    test("check", function()
        local player = game.players[1]
        sandbox.build(player)
        after_ticks(2, function()
            local here = player.position
            local surface = player.surface
            -- the arena only: other fixtures leave vehicles all over the map, and a
            -- search around the player would sweep those up too
            local arena = { { -90, -90 }, { 90, 90 } }
            print(("CHECK player at %.1f,%.1f"):format(here.x, here.y))
            for _, name in ipairs({ "car", "tank", "vp-tests-plane", "vp-tests-boat" }) do
                local found = surface.find_entities_filtered{ name = name, area = arena }
                for _, v in pairs(found) do
                    local dx = v.position.x - here.x
                    print(("CHECK %-16s at %.1f,%.1f  dx=%+.1f (%s)  tile=%s")
                        :format(name, v.position.x, v.position.y, dx,
                                dx >= 0 and "EAST of player" or "WEST of player",
                                surface.get_tile(v.position.x, v.position.y).name))
                    -- how far is it from ground a player can stand on?
                    local nearest = 99
                    for d = 0, 40 do
                        local t = surface.get_tile(v.position.x - d, v.position.y)
                        if t.name ~= "water" and t.name ~= "deepwater" then
                            nearest = d break
                        end
                    end
                    print(("CHECK %-16s %d tiles from walkable ground"):format(name, nearest))
                end
            end

            -- and the question that actually matters for the boat: can it be got into
            -- from dry land? Walk to the end of the pier and try.
            local boat = surface.find_entities_filtered{ name = "vp-tests-boat" }[1]
            assert(boat, "no boat was placed")
            local pier_tip = { x = 52, y = 0 }
            assert.equals("grass-1", surface.get_tile(pier_tip.x, pier_tip.y).name)
            player.driving = false
            local moved = player.teleport(pier_tip, surface)
            print(("CHECK teleport to pier tip returned %s, player now at %.1f,%.1f on %s")
                :format(tostring(moved), player.position.x, player.position.y,
                        surface.get_tile(player.position.x, player.position.y).name))
            print(("CHECK distance to boat centre %.2f, boat at %.1f,%.1f")
                :format(((boat.position.x - player.position.x) ^ 2
                       + (boat.position.y - player.position.y) ^ 2) ^ 0.5,
                        boat.position.x, boat.position.y))
            player.driving = true
            print(("CHECK boarding from the pier: %s (player in %s)")
                :format(tostring(player.vehicle ~= nil),
                        tostring(player.vehicle and player.vehicle.name)))
            assert.equals("vp-tests-boat", player.vehicle and player.vehicle.name,
                "the boat cannot be boarded from the end of the pier")

            -- and it has to be able to leave. A boat collides with ground, so one
            -- moored overlapping the pier boards perfectly well and then sits there.
            for _, corner in ipairs({ { -0.7, 0 }, { 0.7, 0 } }) do
                local tile = surface.get_tile(boat.position.x + corner[1],
                                              boat.position.y + corner[2])
                assert.is_true(tile.name == "water" or tile.name == "deepwater",
                    "the boat is aground on " .. tile.name)
            end
            -- and it has to be able to leave. A boat that boards perfectly well and
            -- then will not move is a boat aground.
            local before = { x = boat.position.x, y = boat.position.y }
            -- through the world helper, which rewrites riding_state every tick: setting
            -- it directly here is overwritten by whatever the last fixture was holding
            world.hold(defines.riding.acceleration.accelerating,
                       defines.riding.direction.straight)
            after_ticks(60, function()
                local moved = ((boat.position.x - before.x) ^ 2
                             + (boat.position.y - before.y) ^ 2) ^ 0.5
                print(("CHECK boat moved %.2f tiles in a second"):format(moved))
                assert.is_true(moved > 1,
                    ("the boat went nowhere: %.2f tiles in a second"):format(moved))
                world.release_controls()
                player.driving = false
            end)
        end)
    end)
end)

--- The switch has to say what is actually happening. Turning it off a tick after boarding
--- has to beat the registration the mod queued when the player got in.
describe("the sandbox switch", function()
    test("off means off, from the moment it is thrown", function()
        local patch = world.patch("refined-concrete")
        local car = patch.drive()
        -- thrown through the sandbox's own switch, the way the hotkey throws it
        sandbox.set(patch.player, false)
        after_ticks(4, function()
            assert.is_nil(storage.cars[car.unit_number],
                "the queued registration put the car back on the books after it was "
                .. "switched off, so the switch read the opposite of the truth")
        end)
    end)
end)
