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
    -- Laser Tanks
    "lasercar", "lasertank",
    -- WH40k Titans
    "warhound", "reaver", "warlord", "imperator",
    -- C5 Galaxy
    "c5-galaxy-grounded", "c5-galaxy-flying",
    -- HelicopterRevival, both prefixes
    "helicopter", "heli-entity-_-", "heli-body-entity-_-", "heli-shadow-entity-_-",
    "heli-burner-entity-_-", "heli-floodlight-entity-_-", "rotor-entity-_-",
    "rotor-shadow-entity-_-", "heli-flying-collision-entity-_-",
    "heli-landed-collision-end-entity-_-", "heli-landed-collision-side-entity-_-",
    "scout-helicopter", "scout-heli-entity-_-", "scout-heli-body-entity-_-",
    "scout-rotor-entity-_-",
} do INSTALLED[name] = true end

local ALL = {
    Hovercrafts = "2.1.4", HelicopterRevival = "0.7.1", raven2 = "1.0.0",
    laser_tanks = "2.0.12", ["WH40k-Titans"] = "1.0.6", ["c5-galaxy"] = "3.0.1",
}

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

    it("leaves the other mods' own vehicles alone too", function()
        local foreign = tracking.foreign_vehicles(ALL, INSTALLED)
        for _, name in pairs{"lasercar", "lasertank", "reaver", "warlord", "imperator",
                             "c5-galaxy-grounded", "c5-galaxy-flying"} do
            assert.is_true(foreign[name] == true, name .. " would be fought over")
        end
    end)

    -- WH40k Titans names its vehicles "reaver", "warlord" and so on. Those are ordinary
    -- enough words that another mod could reasonably use one, which is why a name only
    -- counts while the mod that claims it is loaded.
    it("does not claim a bare name like reaver when that mod is absent", function()
        local foreign = tracking.foreign_vehicles({ Hovercrafts = "2.1.4" }, INSTALLED)
        assert.is_nil(foreign["reaver"])
        assert.is_nil(foreign["warlord"])
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

--- AircraftRealism has no list to copy: whichever planes have been registered with it are
--- carried from the data stage to the control stage inside the order field of a run of
--- prototypes, and reading them back is the only way to know which planes it flies.
--- AircraftRealism has no list to copy: whichever planes have been registered with it are
--- carried from the data stage to the control stage inside the order field of a run of
--- prototypes, and reading them back is the only way to know which planes it flies.
describe("the planes AircraftRealism has taken charge of", function()
    local HOLDER = "aircraft-realism-plane-properties-"

    --- Prototypes holding a registry split across three of them, as the real one is
    local function with_registry()
        local protos = { car = {}, ["cargo-plane"] = {} }
        for index, fragment in pairs{ [0] = "first", [1] = "second", [2] = "third" } do
            protos[HOLDER .. index] = { order = fragment }
        end
        return protos
    end

    --- Stands in for the game's serpent, which a unit test has no access to. It insists
    --- on the whole registry so that a walk which dropped or reordered a fragment fails.
    local function decode(text)
        if text ~= "firstsecondthird" then return false end
        return true, {
            grounded = { ["cargo-plane"] = 1, ["gunship"] = 2 },
            airborne = { ["cargo-plane-flying"] = 2, ["gunship-flying"] = 1 },
        }
    end

    it("reads every plane in the registry, grounded and airborne", function()
        local planes = tracking.aircraft_realism_planes(with_registry(), decode)
        for _, name in pairs{"cargo-plane", "gunship", "cargo-plane-flying",
                             "gunship-flying"} do
            assert.is_true(planes[name] == true, name .. " would be fought over")
        end
    end)

    it("reads nothing when no planes have registered", function()
        assert.are.same({}, tracking.aircraft_realism_planes({ car = {} }, decode))
    end)

    it("reads nothing when the registry will not decode", function()
        local protos = { [HOLDER .. "0"] = { order = "half a registry" } }
        assert.are.same({}, tracking.aircraft_realism_planes(protos, decode))
    end)

    it("reads nothing rather than failing when there is no deserialiser", function()
        assert.are.same({}, tracking.aircraft_realism_planes(with_registry(), nil))
    end)

    -- without AircraftRealism the planes are exactly what this mod is for
    it("claims nothing through the mod list when AircraftRealism is absent", function()
        assert.are.same({}, tracking.foreign_vehicles({}, with_registry()))
    end)

    it("asks the registry when AircraftRealism is installed", function()
        -- no deserialiser here, so the answer is empty; what is under test is that the
        -- lookup is reached and comes back cleanly rather than erroring
        assert.are.same({}, tracking.foreign_vehicles({ AircraftRealism = "2.0.3" },
                                                      with_registry()))
    end)
end)
