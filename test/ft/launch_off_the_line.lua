local world = require("test.ft.world")
local ACCELERATE = defines.riding.acceleration.accelerating

describe("pulling away from a standstill", function()
    local function first_ticks(vehicle, tile, done)
        local patch = world.patch(tile)
        local car = patch.drive(vehicle)
        -- accelerating the instant you are aboard, which is what a player does
        patch.hold(ACCELERATE)
        local speeds = {}
        for sample = 1, 8 do
            after_ticks(sample, function() speeds[sample] = car.speed end)
        end
        after_ticks(9, function()
            world.release_controls()
            done(speeds)
        end)
    end

    test("is gentle for a boat, from the very first tick", function()
        first_ticks("car", "refined-concrete", function(car_speeds)
            first_ticks("vp-tests-boat", "water", function(boat_speeds)
                print(("LAUNCH car  %s"):format(table.concat(
                    (function() local t={} for i,v in ipairs(car_speeds) do
                        t[i]=("%.4f"):format(v) end return t end)(), " ")))
                print(("LAUNCH boat %s"):format(table.concat(
                    (function() local t={} for i,v in ipairs(boat_speeds) do
                        t[i]=("%.4f"):format(v) end return t end)(), " ")))
                -- a quarter of a car's, not most of it, on the first tick it moves
                assert.is_true(boat_speeds[1] < car_speeds[1] * 0.4,
                    ("off the line the boat did %.4f against the car's %.4f")
                        :format(boat_speeds[1], car_speeds[1]))

                -- and it eases in rather than jumping in. The game's acceleration is at
                -- its hardest from a standstill -- a car gains more in its first tick
                -- than in its next two together -- and simply scaling that down keeps
                -- the same jump, only smaller.
                local first = boat_speeds[1]
                local second = boat_speeds[2] - boat_speeds[1]
                assert.is_true(first < second,
                    ("the boat's first tick gained %.5f and its second %.5f, so it is "
                     .. "still jumping off the line"):format(first, second))
                assert.is_true(car_speeds[1] > (car_speeds[2] - car_speeds[1]),
                    "a car is supposed to keep the game's punch off the line")
            end)
        end)
    end)
end)
