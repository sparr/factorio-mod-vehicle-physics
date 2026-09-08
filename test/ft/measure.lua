--- Not a test: a measuring run.
---
--- Drives every vehicle through the same three manoeuvres, once with the mod holding the
--- wheel and once without, and writes what happened to a csv for plotting. "Without"
--- means the car is taken off storage.cars -- the mod only acts on what it has on its
--- books, so a car that is not on them runs on the game's own physics while still being
--- perfectly driveable.
---
--- Tagged and blacklisted, because it takes ten thousand ticks and answers a question
--- nobody asks on every run:
---
---   test/ft/run.sh --tag-whitelist measure
local world = require("test.ft.world")

local ACCELERATE = defines.riding.acceleration.accelerating
local BRAKE = defines.riding.acceleration.braking
local NOTHING = defines.riding.acceleration.nothing
local LEFT = defines.riding.direction.left
local STRAIGHT = defines.riding.direction.straight

local GROUND = { car = "refined-concrete", tank = "refined-concrete",
                 ["vp-tests-boat"] = "water", ["vp-tests-plane"] = "refined-concrete" }
--- Braking and turning are measured from several speeds, by giving the vehicle different
--- amounts of run-up first. Measuring only from full speed says nothing about how any of
--- this behaves at the speeds most driving actually happens at.
local SPIN_UPS = { 20, 45, 90, 240 }
local SAMPLES = 240

local rows = { "vehicle,modded,manoeuvre,spinup,tick,speed,orientation,x,y" }

-- tags() applies to the next thing registered, so it goes before the block rather than
-- inside it: inside, it would tag only the first test of the twenty five
tags("measure")
describe("measurements", function()
    for _, vehicle in ipairs({ "car", "tank", "vp-tests-boat", "vp-tests-plane" }) do
        for _, modded in ipairs({ true, false }) do
            local runs = { { "accelerate", 0 } }
            for _, spin in ipairs(SPIN_UPS) do
                runs[#runs + 1] = { "brake", spin }
                runs[#runs + 1] = { "turn", spin }
            end
            for _, run in ipairs(runs) do
                local manoeuvre, spin_up = run[1], run[2]
                local label = ("%s %s %s %d"):format(vehicle,
                    modded and "modded" or "vanilla", manoeuvre, spin_up)

                test(label, function()
                    local arena = world.arena(GROUND[vehicle])
                    local car = world.launch(arena, vehicle)
                    world.hold(NOTHING, STRAIGHT)

                    after_ticks(3, function()
                        -- the control car comes off the books, and is then on the
                        -- game's own physics for the rest of the run
                        if not modded then storage.cars[car.unit_number] = nil end

                        local function record()
                            world.hold(manoeuvre == "brake" and BRAKE or ACCELERATE,
                                       manoeuvre == "turn" and LEFT or STRAIGHT)
                            for sample = 1, SAMPLES do
                                after_ticks(sample, function()
                                    rows[#rows + 1] = ("%s,%s,%s,%d,%d,%.6f,%.6f,%.3f,%.3f")
                                        :format(vehicle, tostring(modded), manoeuvre,
                                                spin_up, sample, car.speed, car.orientation,
                                                car.position.x - arena.centre.x,
                                                car.position.y - arena.centre.y)
                                end)
                            end
                        end

                        if manoeuvre == "accelerate" then
                            record()
                        else
                            world.hold(ACCELERATE, STRAIGHT)
                            after_ticks(spin_up, record)
                        end
                    end)
                end)
            end
        end
    end

    test("write the csv", function()
        helpers.write_file("vehicle-physics-measurements.csv",
                           table.concat(rows, "\n") .. "\n")
        print("MEASURE rows " .. #rows)
    end)
end)
