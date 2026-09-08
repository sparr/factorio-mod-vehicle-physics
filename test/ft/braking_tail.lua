--- What the last moments of a brake look like. The game finishes a brake by snapping a
--- small speed to nothing; a kind that brakes a quarter as hard should not arrive at a
--- standstill in one tick regardless.
local world = require("test.ft.world")

local BRAKE = defines.riding.acceleration.braking
local ACCELERATE = defines.riding.acceleration.accelerating

---@param suppress boolean? take the vehicle off the mod's books before braking
local function stopping_tail(vehicle, tile, done, suppress)
    local patch = world.patch(tile)
    local car = patch.drive(vehicle)
    if suppress then storage.cars[car.unit_number] = nil end
    patch.hold(ACCELERATE)
    after_ticks(120, function()
        patch.hold(BRAKE)
        local speeds = {}
        for sample = 1, 700 do
            after_ticks(sample, function()
                if car.valid then speeds[sample] = car.speed end
            end)
        end
        after_ticks(701, function()
            world.release_controls()
            done(speeds)
        end)
    end)
end

--- The last step into a standstill, and the step before it. A stop that ramps has the two
--- in the same ballpark; a stop that lurches has a cliff at the end.
local function last_two_steps(speeds)
    for i = 3, #speeds do
        if speeds[i] == 0 and speeds[i - 1] > 0 then
            return speeds[i - 1], speeds[i - 2] - speeds[i - 1], i
        end
    end
    return nil
end

describe("the end of a brake", function()
    --- Not "the mod leaves a car alone": it does not. The drift scrubs speed off, so a
    --- car on the mod's books stops at tick 80 from 0.054 where the same car off them
    --- stops at tick 93 from 0.030. What matters is that the stop ramps rather than
    --- falling off a cliff, and that is true of both.
    local function ramps_into_the_stop(vehicle, tile)
        stopping_tail(vehicle, tile, function(speeds)
            local last, previous, at = last_two_steps(speeds)
            assert.is_not_nil(last, vehicle .. " never came to a stop")
            print(("TAIL %-14s stopped at tick %d, last step %.5f, the one before %.5f")
                :format(vehicle, at, last, previous))
            -- Either the step is in keeping with the one before it, or it is too small
            -- to feel at all. A kind that brakes at a tenth decays geometrically, so its
            -- final step is always a large multiple of the step before -- but at five
            -- thousandths of a tile per tick, which is a fortieth of a tile per second,
            -- there is nothing there to feel.
            assert.is_true(last < previous * 3 or last < 0.005,
                ("%s dropped %.5f into the stop after a step of %.5f, which is a lurch")
                    :format(vehicle, last, previous))
        end)
    end

    test("ramps into it for a car", function()
        ramps_into_the_stop("car", "refined-concrete")
    end)

    --- A boat brakes a quarter as hard, so its approach is flat and the game's last step
    --- stood out a mile: it went from a tenth of a tile per tick to nothing in one tick.
    test("ramps into it for a boat too", function()
        ramps_into_the_stop("vp-tests-boat", "water")
    end)

    test("and for an aircraft, which brakes gentlest of all", function()
        ramps_into_the_stop("vp-tests-plane", "refined-concrete")
    end)
end)
