local tracking = require("lib.tracking")

--- Every car-type prototype the six surveyed vehicle mods put in a 2.1.17 game, taken
--- from a load of all of them together. The names another mod drives itself are the
--- point of the list; the rest are here so that over-excluding shows up as a failure.
local INSTALLED = {}
for _, name in pairs{
    "car", "tank",
    -- Aircraft
    "cargo-plane", "cargo-plane-carbon-fiber", "gunship", "gunship-carbon-fiber",
    "jet", "jet-carbon-fiber", "flying-fortress", "flying-fortress-carbon-fiber",
    -- boats
    "indep-boat", "ironclad",
    -- Hovercrafts
    "hovercraft", "electric-hovercraft", "missile-hovercraft", "laser-hovercraft",
    "hovercraft-collision",
    -- HelicopterRevival, both prefixes
    "helicopter", "heli-entity-_-", "heli-body-entity-_-", "heli-shadow-entity-_-",
    "heli-burner-entity-_-", "heli-floodlight-entity-_-", "rotor-entity-_-",
    "rotor-shadow-entity-_-", "heli-flying-collision-entity-_-",
    "heli-landed-collision-end-entity-_-", "heli-landed-collision-side-entity-_-",
    "scout-helicopter", "scout-heli-entity-_-", "scout-heli-body-entity-_-",
    "scout-rotor-entity-_-",
} do INSTALLED[name] = true end

local ALL = { Hovercrafts = "2.1.4", HelicopterRevival = "0.7.1", raven2 = "1.0.0" }

describe("vehicles another mod drives itself", function()
    it("leaves Hovercrafts' four craft alone", function()
        local foreign = tracking.foreign_vehicles(ALL, INSTALLED)
        for _, name in pairs{"hovercraft", "electric-hovercraft", "missile-hovercraft",
                             "laser-hovercraft"} do
            assert.is_true(foreign[name] == true, name .. " would be fought over")
        end
    end)

    it("leaves both helicopters and their parts alone", function()
        local foreign = tracking.foreign_vehicles(ALL, INSTALLED)
        for _, name in pairs{"heli-entity-_-", "scout-heli-entity-_-", "helicopter",
                             "scout-helicopter", "rotor-entity-_-"} do
            assert.is_true(foreign[name] == true, name .. " would be fought over")
        end
    end)

    it("keeps its hands on everything else, which is the point of the mod", function()
        local foreign = tracking.foreign_vehicles(ALL, INSTALLED)
        for _, name in pairs{"car", "tank", "cargo-plane", "jet", "flying-fortress",
                             "indep-boat", "ironclad"} do
            assert.is_nil(foreign[name], name .. " was excluded and should not be")
        end
    end)

    -- a name is only a claim while the mod that makes it is loaded, so an unrelated mod
    -- shipping a vehicle called "hovercraft" still gets the physics
    it("claims nothing when none of those mods are installed", function()
        assert.are.same({}, tracking.foreign_vehicles({}, INSTALLED))
    end)

    it("claims only what the installed mod owns", function()
        local foreign = tracking.foreign_vehicles({ Hovercrafts = "2.1.4" }, INSTALLED)
        assert.is_true(foreign["hovercraft"] == true)
        assert.is_nil(foreign["heli-entity-_-"])
    end)
end)
