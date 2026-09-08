--- Telling a car from a boat from an aircraft, and what that changes.
local world = require("test.ft.world")
local tracking = require("lib.tracking")

local ACCELERATE = defines.riding.acceleration.accelerating
local LEFT = defines.riding.direction.left

describe("what a vehicle is", function()
    test("is read off what it collides with", function()
        assert.equals("ground", tracking.kind("car"))
        assert.equals("ground", tracking.kind("tank"))
        assert.equals("boat", tracking.kind("vp-tests-boat"))
        assert.equals("flying", tracking.kind("vp-tests-plane"))
    end)

    test("is worked out once and remembered", function()
        storage.vehicle_kind = {}
        tracking.kind("car")
        assert.equals("ground", storage.vehicle_kind["car"])
        -- and the remembered answer is the one that comes back
        storage.vehicle_kind["car"] = "boat"
        assert.equals("boat", tracking.kind("car"))
        storage.vehicle_kind = {}
    end)
end)

describe("how each kind handles", function()
    test("is set as multiples of what a car does", function()
        local car = tracking.HANDLING.ground
        assert.equals(1, car.accelerating)
        assert.equals(1, car.braking)
        assert.equals(1, car.drift)
        assert.equals(1, car.rotate)

        local boat, plane = tracking.HANDLING.boat, tracking.HANDLING.flying
        assert.is_true(boat.accelerating < car.accelerating,
            "a boat should not pick up speed as readily as a car")
        assert.is_true(plane.accelerating < boat.accelerating,
            "an aircraft should pick up speed even less readily than a boat")
        assert.is_true(boat.drift > car.drift and plane.drift > boat.drift,
            "a boat should slide more than a car, and an aircraft more than a boat")
        assert.is_true(boat.rotate < car.rotate and plane.rotate > boat.rotate,
            "a boat should be the most sluggish thing to turn")
    end)

    --- The drift figure is a multiple of how much a car slides, and has to come out as a
    --- share of drift kept per tick that rises with it.
    test("turns the drift multiple into what the physics actually uses", function()
        local car = tracking.drift_multiplier("ground", false)
        local boat = tracking.drift_multiplier("boat", false)
        local plane = tracking.drift_multiplier("flying", false)
        assert.equals(0.865, car)
        assert.is_true(boat > car and plane > boat,
            ("kept per tick: car %.4f, boat %.4f, aircraft %.4f"):format(car, boat, plane))
        -- a boat corrects a quarter as much of its drift as a car does
        assert.is_true(math.abs((1 - boat) * 4 - (1 - car)) < 1e-9)
        assert.is_true(math.abs((1 - plane) * 10 - (1 - car)) < 1e-9)
    end)
end)

--- The behaviour, rather than the numbers behind it. A car and an aircraft can both be on
--- land, so they can be driven through the same corner and compared.
describe("an aircraft against a car, through the same corner", function()
    local function corner(name, done)
        local patch = world.patch("refined-concrete")
        local car = patch.drive(name)
        local start = { x = car.position.x, y = car.position.y }
        patch.hold(ACCELERATE)
        after_ticks(60, function()
            patch.hold(ACCELERATE, LEFT)
            after_ticks(45, function()
                done(patch, car, start)
            end)
        end)
    end

    test("carries on further in the direction it was already going", function()
        corner("car", function(_, car, start)
            local ground = { dx = car.position.x - start.x, dy = car.position.y - start.y }
            corner("vp-tests-plane", function(_, plane, plane_start)
                local air = { dx = plane.position.x - plane_start.x,
                              dy = plane.position.y - plane_start.y }
                local apart = ((air.dx - ground.dx) ^ 2 + (air.dy - ground.dy) ^ 2) ^ 0.5
                assert.is_true(apart > 1,
                    ("both took the same line through the corner, %f apart"):format(apart))
            end)
        end)
    end)
end)

--- What the ground gets marked with, which is nothing at all unless there are wheels on it
describe("marks on the ground", function()
    local function handbrake(name, tile, done)
        local patch = world.patch(tile)
        local car = patch.drive(name)
        patch.hold(ACCELERATE)
        after_ticks(60, function()
            patch.hold(ACCELERATE, LEFT)
            after_ticks(30, function()
                patch.hold(defines.riding.acceleration.braking, LEFT)
                after_ticks(40, function() done(patch) end)
            end)
        end)
    end

    test("are left by a car", function()
        handbrake("car", "refined-concrete", function(patch)
            assert.is_true(patch.count("drifting-tire-marks") > 0,
                "setup: a car left no marks to compare against")
        end)
    end)

    test("are not left by an aircraft", function()
        handbrake("vp-tests-plane", "refined-concrete", function(patch)
            assert.equals(0, patch.count("drifting-tire-marks"),
                "an aircraft left tire marks on the ground")
            assert.equals(0, patch.count("drifting-tire-marks-faded"))
        end)
    end)

    test("are not left by a boat", function()
        handbrake("vp-tests-boat", "water", function(patch)
            assert.equals(0, patch.count("drifting-tire-marks"),
                "a boat left tire marks on the water")
            assert.equals(0, patch.count("drifting-tire-marks-faded"))
        end)
    end)
end)

--- An aircraft slides ten times as readily as a car, and sliding scrubs speed off. If
--- that scrub is not divided by how much the kind slides, an aircraft scrubs ten times as
--- hard as a car and slams to a stop coming out of a turn, or off the end of a brake.
describe("an aircraft coming out of a slide", function()
    test("loses its speed smoothly rather than stopping dead", function()
        local patch = world.patch("refined-concrete")
        local plane = patch.drive("vp-tests-plane")
        patch.hold(ACCELERATE)
        after_ticks(120, function()
            -- turned across its own line, which is where the drift is largest
            patch.hold(ACCELERATE, LEFT)
            after_ticks(60, function()
                local entry = plane.speed
                assert.is_true(entry > 0.05, "setup: never got moving, at " .. entry)
                patch.hold(defines.riding.acceleration.nothing, LEFT)

                local speeds = {}
                for sample = 1, 90 do
                    after_ticks(sample, function() speeds[sample] = plane.speed end)
                end
                after_ticks(91, function()
                    local worst, worst_at = 0, 0
                    for i = 2, #speeds do
                        local drop = speeds[i - 1] - speeds[i]
                        if drop > worst then worst, worst_at = drop, i end
                    end
                    -- Measured both ways to set these: with the scrub divided by how
                    -- much the kind slides an aircraft keeps 94% of its speed through
                    -- the coast and never loses more than 0.0002 in a tick; without, it
                    -- keeps 61% and sheds five times as much in its worst tick.
                    local kept = speeds[#speeds] / entry
                    assert.is_true(kept > 0.85,
                        ("it kept only %.0f%% of its speed coasting out of the turn, "
                         .. "%.4f down to %.4f"):format(kept * 100, entry, speeds[#speeds]))
                    assert.is_true(worst < 0.0005,
                        ("it lost %.5f of its speed in a single tick at tick %d")
                            :format(worst, worst_at))
                end)
            end)
        end)
    end)
end)

--- The drift moves a vehicle by teleporting it, and a teleport asks nothing about where it
--- is going. A boat put on the beach sticks there: every direction out is land too.
describe("a boat driven at the shore", function()
    test("never ends up aground", function()
        -- water to the west, land from x=0 east, and the boat pointed at the beach
        local patch = world.patch("water")
        local surface = patch.surface
        local beach = {}
        for x = patch.left + 40, patch.left + 96 - 1 do
            for y = patch.top, patch.top + 96 - 1 do
                beach[#beach + 1] = { name = "grass-1", position = { x, y } }
            end
        end
        surface.set_tiles(beach)

        local boat = patch.drive("vp-tests-boat")
        boat.teleport({ patch.left + 20, patch.top + 48 })
        patch.player.teleport(boat.position, surface)
        boat.orientation = 0.25          -- pointed east, at the beach

        patch.hold(ACCELERATE)
        after_ticks(90, function()
            -- and then stand on the brake, which is when it used to climb out
            patch.hold(defines.riding.acceleration.braking)
            local aground = false
            for sample = 1, 90 do
                after_ticks(sample, function()
                    if boat.valid and tracking.aground(boat, boat.position) then
                        aground = true
                    end
                end)
            end
            after_ticks(91, function()
                assert.is_false(aground,
                    "the boat was put on the beach, where it cannot move")
                world.release_controls()
            end)
        end)
    end)
end)
