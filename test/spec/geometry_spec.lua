local geometry = require("lib.geometry")

--- Factorio's orientation is a turn from 0 to 1, north at zero, increasing clockwise,
--- with y growing downwards. These are the four that have exact answers.
local NORTH, EAST, SOUTH, WEST = 0, 0.25, 0.5, 0.75

local function close(a, b, tolerance)
    return math.abs(a - b) < (tolerance or 1e-9)
end

describe("projection", function()
    it("sends north up the screen, which is negative y", function()
        local point = geometry.projection(NORTH, 5)
        assert.is_true(close(point.x, 0), point.x)
        assert.is_true(close(point.y, -5), point.y)
    end)

    it("sends east and west along x", function()
        assert.is_true(close(geometry.projection(EAST, 3).x, 3))
        assert.is_true(close(geometry.projection(EAST, 3).y, 0))
        assert.is_true(close(geometry.projection(WEST, 3).x, -3))
    end)

    it("sends south down the screen", function()
        assert.is_true(close(geometry.projection(SOUTH, 2).y, 2))
    end)

    it("measures from wherever it is told to", function()
        local point = geometry.projection(EAST, 4, { x = 10, y = -10 })
        assert.is_true(close(point.x, 14), point.x)
        assert.is_true(close(point.y, -10), point.y)
    end)

    it("takes a negative distance as the opposite way, which is what reversing is", function()
        local forward = geometry.projection(EAST, 4)
        local backward = geometry.projection(EAST, -4)
        assert.is_true(close(forward.x, -backward.x))
    end)

    it("comes back to where it started after a whole turn", function()
        local once = geometry.projection(0.3, 7)
        local again = geometry.projection(1.3, 7)
        assert.is_true(close(once.x, again.x), once.x .. " vs " .. again.x)
        assert.is_true(close(once.y, again.y))
    end)
end)

describe("orientation_from_coords", function()
    it("reads the four quarters back", function()
        assert.is_true(close(geometry.orientation_from_coords{ x = 0, y = -1 }, NORTH))
        assert.is_true(close(geometry.orientation_from_coords{ x = 1, y = 0 }, EAST))
        assert.is_true(close(geometry.orientation_from_coords{ x = 0, y = 1 }, SOUTH))
        assert.is_true(close(geometry.orientation_from_coords{ x = -1, y = 0 }, WEST))
    end)

    it("does not care how long the vector is", function()
        assert.is_true(close(geometry.orientation_from_coords{ x = 9, y = 0 }, EAST))
        assert.is_true(close(geometry.orientation_from_coords{ x = 0.001, y = 0 }, EAST))
    end)

    -- the physics asks how far a car's drift has come away from the way it is facing,
    -- so the two have to be the same measurement read the same way round
    it("undoes projection", function()
        for _, orientation in ipairs({ 0, 0.1, 0.25, 0.4, 0.5, 0.6, 0.75, 0.9 }) do
            local read = geometry.orientation_from_coords(geometry.projection(orientation, 3))
            assert.is_true(close(read % 1, orientation, 1e-9),
                orientation .. " came back as " .. read)
        end
    end)
end)

describe("distance", function()
    it("is the straight line between two points", function()
        assert.equals(5, geometry.distance({ x = 0, y = 0 }, { x = 3, y = 4 }))
    end)

    it("is zero for a point and itself", function()
        assert.equals(0, geometry.distance({ x = 2, y = 2 }, { x = 2, y = 2 }))
    end)

    it("does not care which way round it is asked", function()
        local a, b = { x = -1, y = 7 }, { x = 4, y = -2 }
        assert.equals(geometry.distance(a, b), geometry.distance(b, a))
    end)
end)

describe("max_range", function()
    it("pulls a far point in to the range asked for", function()
        local held = geometry.max_range({ x = 0, y = 0 }, { x = 10, y = 0 }, 4)
        assert.is_true(close(held.x, 4), held.x)
        assert.is_true(close(held.y, 0))
    end)

    it("leaves a point already within range where it is", function()
        local held = geometry.max_range({ x = 0, y = 0 }, { x = 1, y = 0 }, 4)
        assert.is_true(close(held.x, 1), held.x)
    end)

    it("keeps the direction it was pulled along", function()
        local held = geometry.max_range({ x = 0, y = 0 }, { x = 6, y = 8 }, 5)
        -- the same 3:4 slope, at length 5
        assert.is_true(close(held.x, 3), held.x)
        assert.is_true(close(held.y, 4), held.y)
    end)
end)
