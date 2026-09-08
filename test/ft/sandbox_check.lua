--- Verifies where the sandbox actually puts things, so it is never launched on a guess.
local sandbox = require("test.sandbox")

describe("sandbox placement", function()
    test("check", function()
        local player = game.players[1]
        sandbox.build(player)
        after_ticks(2, function()
            local here = player.position
            local surface = player.surface
            print(("CHECK player at %.1f,%.1f"):format(here.x, here.y))
            for _, name in ipairs({ "car", "tank", "vp-tests-plane", "vp-tests-boat" }) do
                local found = surface.find_entities_filtered{ name = name,
                    area = { { here.x - 300, here.y - 300 }, { here.x + 300, here.y + 300 } } }
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
            player.driving = false
        end)
    end)
end)
