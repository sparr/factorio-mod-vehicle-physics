--- The two ways a driven car used to end up off the mod's books, or on them with nobody
--- in it. Neither needs a mod to reproduce; both are things ordinary play does.
local world = require("test.ft.world")
local tracking = require("lib.tracking")

describe("a car somebody was already sitting in", function()
    --- What a fresh install looks like from the mod's side: the tables are empty and no
    --- event is coming, because the player got in before the mod existed.
    test("is picked up when the mod starts up", function()
        local patch = world.patch("refined-concrete")
        local car = patch.drive()
        after_ticks(2, function()
            assert.is_not_nil(world.tracked(car), "setup: never tracked in the first place")
            storage.cars = {}
            assert.is_nil(world.tracked(car), "setup: the table was not emptied")

            -- what on_init and on_configuration_changed now do
            tracking.adopt()
            assert.is_not_nil(world.tracked(car),
                "a player already at the wheel was never picked up")
        end)
    end)
end)

describe("getting in and straight back out again", function()
    test("leaves nothing on the books", function()
        local patch = world.patch("refined-concrete")
        local car = patch.drive()
        patch.player.driving = false
        after_ticks(3, function()
            assert.is_nil(world.tracked(car),
                "a car with nobody in it is being tracked, for good")
            assert.is_nil(car.get_driver(), "setup: somebody is still driving it")
        end)
    end)
end)
