--- What the last moments of a brake look like. The game finishes a brake by snapping a
--- small speed to nothing; a kind that brakes a quarter as hard should not arrive at a
--- standstill in one tick regardless.
local world = require("test.ft.world")

local BRAKE = defines.riding.acceleration.braking
local ACCELERATE = defines.riding.acceleration.accelerating

local function stopping_tail(vehicle, tile, done)
    local patch = world.patch(tile)
    local car = patch.drive(vehicle)
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

--- the size of the last drop before it reaches a standstill
local function final_drop(speeds)
    for i = 2, #speeds do
        if speeds[i] == 0 and speeds[i - 1] > 0 then
            return speeds[i - 1], i
        end
    end
    return nil
end

describe("the end of a brake", function()
    --- A car is not scaled at all, so its stop is the game's own and this is here to say
    --- what that looks like: the brake ramps up and takes the last of it in one step.
    test("is the game's own for a car, which the mod does not touch", function()
        stopping_tail("car", "refined-concrete", function(speeds)
            local last, at = final_drop(speeds)
            assert.is_not_nil(last, "the car never came to a stop")
            print(("TAIL car stopped at tick %d from %.5f"):format(at, last))
            assert.is_true(last > 0.02,
                "the car's stop has changed; it is supposed to be untouched")
        end)
    end)

    --- A boat brakes a quarter as hard, so its speed comes down gently -- and then the
    --- game used to take the last tenth of a tile per tick off in a single step, which is
    --- a lurch you feel. It should ease in, from slower than a car does.
    test("eases in for a boat rather than lurching", function()
        stopping_tail("vp-tests-boat", "water", function(speeds)
            local last, at = final_drop(speeds)
            assert.is_not_nil(last, "the boat never came to a stop")
            print(("TAIL boat stopped at tick %d from %.5f"):format(at, last))
            assert.is_true(last < 0.02,
                ("the boat dropped %.5f straight to nothing, which is the lurch at the "
                 .. "end of a deceleration"):format(last))
        end)
    end)
end)
