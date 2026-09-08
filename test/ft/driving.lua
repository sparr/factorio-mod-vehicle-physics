--- Driving a car and watching what the physics does to it.
---
--- Every one of these holds the controls the way a player holds a key, by writing
--- riding_state, and lets the game run. Nothing here presses a key or fakes an input
--- event: riding_state is writable, so the mod's on_tick sees exactly what it would see
--- with somebody at the keyboard.
local world = require("test.ft.world")

local ACCELERATE = defines.riding.acceleration.accelerating
local BRAKE = defines.riding.acceleration.braking
local NOTHING = defines.riding.acceleration.nothing
local LEFT = defines.riding.direction.left
local STRAIGHT = defines.riding.direction.straight

describe("getting into a car", function()
    test("is noticed, a tick later", function()
        local patch = world.patch("refined-concrete")
        local car = patch.drive()
        -- the mod waits a tick on purpose: at the moment the event fires the car has
        -- not moved, and the physics wants a position and a speed to work from
        assert.is_nil(world.tracked(car), "tracked before the tick it waits for")
        after_ticks(2, function()
            local record = world.tracked(car)
            assert.is_not_nil(record, "the car was never picked up")
            assert.equals(car.unit_number, record.entity.unit_number)
            assert.same({ x = 0, y = 0 }, record.drift)
        end)
    end)

    test("puts nothing in the save that a save cannot hold", function()
        local patch = world.patch("refined-concrete")
        patch.drive()
        -- a function here is what used to make saving fail outright
        for _, queued in pairs(storage.entering) do
            for _, entry in pairs(queued) do
                assert.is_not.equal("function", type(entry),
                    "a function is waiting in the save table")
                assert.equals("userdata", type(entry))
            end
        end
    end)
end)

describe("getting out again", function()
    test("stops the car being tracked", function()
        local patch = world.patch("refined-concrete")
        local car = patch.drive()
        after_ticks(2, function()
            assert.is_not_nil(world.tracked(car))
            patch.player.driving = false
            after_ticks(1, function()
                assert.is_nil(world.tracked(car), "still tracked after getting out")
            end)
        end)
    end)
end)

describe("a tank", function()
    test("is tracked apart from the cars", function()
        local patch = world.patch("refined-concrete")
        local tank = patch.drive("tank")
        after_ticks(2, function()
            assert.is_not_nil(world.tracked_tank(tank), "the tank was not picked up")
            assert.is_nil(world.tracked(tank), "the tank was filed as a car")
        end)
    end)
end)

describe("holding the accelerator", function()
    test("gets the car moving", function()
        local patch = world.patch("refined-concrete")
        local car = patch.drive()
        after_ticks(2, function()
            assert.equals(0, car.speed)
            patch.hold(ACCELERATE)
            after_ticks(60, function()
                assert.is_true(car.speed > 0.1,
                    "a second of accelerating only reached " .. car.speed)
            end)
        end)
    end)

    test("and then the brake slows it again", function()
        local patch = world.patch("refined-concrete")
        local car = patch.drive()
        patch.hold(ACCELERATE)
        after_ticks(60, function()
            local moving = car.speed
            assert.is_true(moving > 0.1, "never got going: " .. moving)
            patch.hold(BRAKE)
            after_ticks(30, function()
                assert.is_true(car.speed < moving,
                    "braking left it at " .. car.speed .. ", was " .. moving)
            end)
        end)
    end)
end)

--- The point of the whole mod: a car carries on in the direction it was going, and how
--- much depends on what is under it.
describe("turning at speed", function()
    --- Get up to speed, turn into it, then stand on the brake: the marks and the noise
    --- belong to braking, which is what a handbrake turn is. `braking` is how long to
    --- stay on the brake before looking, because the drift is only there while the car
    --- is still moving -- the mod zeroes it the moment the car comes to rest.
    local function handbrake_turn(tile, braking, done)
        local patch = world.patch(tile)
        local car = patch.drive()
        patch.hold(ACCELERATE)
        -- long enough to be moving properly, short enough to stay on the paving: at full
        -- tilt a car crosses the whole patch and the test ends up measuring bare nauvis
        after_ticks(60, function()
            patch.hold(ACCELERATE, LEFT)
            after_ticks(30, function()
                patch.hold(BRAKE, LEFT)
                after_ticks(braking, function()
                    done(patch, car, world.tracked(car))
                end)
            end)
        end)
    end

    --- Asserting the drift is merely non-zero proves nothing: the mod seeds it from the
    --- car's speed the moment it starts tracking, so it is non-zero whether or not the
    --- physics ever runs again. What matters is that it keeps being worked out.
    test("keeps working the drift out as the car slides", function()
        handbrake_turn("refined-concrete", 10, function(patch, car, record)
            assert.is_not_nil(record, "the car stopped being tracked")
            assert.is_true(math.abs(car.speed) > 0,
                "the car had already stopped, so there is no drift to speak of")
            local before = { x = record.drift.x, y = record.drift.y }
            assert.is_true((before.x ^ 2 + before.y ^ 2) ^ 0.5 > 0,
                "the car is not drifting at all")
            after_ticks(10, function()
                local now = world.tracked(car)
                assert.is_not_nil(now, "the car stopped being tracked")
                local moved = ((now.drift.x - before.x) ^ 2 +
                               (now.drift.y - before.y) ^ 2) ^ 0.5
                assert.is_true(moved > 0.001,
                    ("the drift has not been touched in ten ticks: %f, %f"):format(
                        now.drift.x, now.drift.y))
            end)
        end)
    end)

    test("marks the ground it slid over", function()
        handbrake_turn("refined-concrete", 40, function(patch)
            assert.is_true(patch.count("drifting-tire-marks") > 0,
                "no tire marks were left on the pavement")
        end)
    end)

    test("leaves the faded kind on loose ground", function()
        handbrake_turn("sand-1", 40, function(patch)
            assert.is_true(patch.count("drifting-tire-marks-faded") > 0,
                "no faded marks were left on sand")
            assert.equals(0, patch.count("drifting-tire-marks"),
                "the dark pavement marks were used on sand")
        end)
    end)
end)

describe("a car nobody is touching", function()
    test("is left where it is", function()
        local patch = world.patch("refined-concrete")
        local car = patch.drive()
        patch.hold(NOTHING, STRAIGHT)
        after_ticks(2, function()
            local resting = car.position
            after_ticks(60, function()
                assert.is_true(math.abs(car.position.x - resting.x) < 0.01, "it drifted off")
                assert.is_true(math.abs(car.position.y - resting.y) < 0.01, "it drifted off")
                assert.equals(0, car.speed)
            end)
        end)
    end)
end)

--- Everything above shows the mod keeping its own books: its drift record, its tire
--- marks. None of it shows the car driving any differently from a stock one, which is
--- the whole claim of the mod.
---
--- The mod only touches cars it has in storage.cars. Taking a car out of there leaves it
--- on the game's own physics while it is still perfectly driveable, so the same drive can
--- be run twice -- once with the mod holding the wheel and once without -- and the two
--- compared. The game is deterministic, the inputs are identical, so anything that
--- differs is the mod.
describe("against the game's own physics", function()
    local ACCELERATE_FOR, TURN_FOR = 60, 30

    --- @param suppress boolean take the car off the mod's books before driving
    local function drive(suppress, done)
        local patch = world.patch("refined-concrete")
        local car = patch.drive()
        local start = { x = car.position.x, y = car.position.y }
        after_ticks(2, function()
            assert.is_not_nil(world.tracked(car), "the car was never picked up")
            if suppress then storage.cars[car.unit_number] = nil end
            patch.hold(ACCELERATE)
            after_ticks(ACCELERATE_FOR, function()
                patch.hold(ACCELERATE, LEFT)
                after_ticks(TURN_FOR, function()
                    done({
                        speed = car.speed,
                        orientation = car.orientation,
                        -- where it ended up relative to where it set off, which is
                        -- comparable between two runs in different corners of the map
                        dx = car.position.x - start.x,
                        dy = car.position.y - start.y,
                        tracked = world.tracked(car) ~= nil,
                    })
                end)
            end)
        end)
    end

    test("the same drive comes out slower with the mod holding the wheel", function()
        drive(true, function(stock)
            assert.is_false(stock.tracked, "the control car was still on the mod's books")
            drive(false, function(modded)
                assert.is_true(modded.tracked, "the modded car fell off the mod's books")
                assert.is_true(modded.speed < stock.speed,
                    ("the mod made no difference to speed: %f with, %f without")
                        :format(modded.speed, stock.speed))
                -- and by a margin worth having, not a rounding error
                assert.is_true(stock.speed - modded.speed > 0.01,
                    ("only %f apart"):format(stock.speed - modded.speed))
            end)
        end)
    end)

    test("and ends up somewhere else, having drifted through the corner", function()
        drive(true, function(stock)
            drive(false, function(modded)
                -- not how far, but where: the two take different lines through the same
                -- corner and finish a couple of tiles apart, having covered much the
                -- same ground getting there
                local apart = ((modded.dx - stock.dx) ^ 2 +
                               (modded.dy - stock.dy) ^ 2) ^ 0.5
                assert.is_true(apart > 1,
                    ("both cars took the same line, finishing %f apart"):format(apart))
                assert.is_true(math.abs(modded.orientation - stock.orientation) > 0.001,
                    ("both cars ended up facing the same way: %f and %f")
                        :format(modded.orientation, stock.orientation))
            end)
        end)
    end)
end)
