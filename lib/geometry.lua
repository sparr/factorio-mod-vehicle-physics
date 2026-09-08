--- The trigonometry the physics is built on. Nothing here touches the game, which is what
--- lets the unit tier drive it with plain numbers.
---
--- Orientation is Factorio's: a turn from 0 to 1, zero pointing north and increasing
--- clockwise, so 0.25 is east and 0.5 is south. y grows downwards.
local geometry = {}

--- A point `distance` away from `position` in the direction `orientation` faces.
--- Used to turn a vehicle's speed into the drift vector the physics carries around.
---@param orientation number a turn, 0 to 1
---@param distance number
---@param position MapPosition?
---@return MapPosition
function geometry.projection(orientation, distance, position)
    if not position then position = { x = 0, y = 0 } end
    local temp_x = math.sin((orientation + 0) * 2 * math.pi) * distance
    local temp_y = math.sin((orientation + 0.75) * 2 * math.pi) * distance
    return { x = temp_x + position.x, y = temp_y + position.y }
end

--- The orientation a vector points in: the inverse of projection, for asking how far a
--- car's drift has come away from the way it is facing.
---@param coords MapPosition
---@return number a turn, 0 to 1
function geometry.orientation_from_coords(coords)
    return (math.atan2(coords.x, coords.y) / math.pi / 2 - 0.5) * -1
end

---@param pos1 MapPosition
---@param pos2 MapPosition
---@return number
function geometry.distance(pos1, pos2)
    local x = (pos1.x - pos2.x) ^ 2
    local y = (pos1.y - pos2.y) ^ 2
    return (x + y) ^ 0.5
end

--- Pull `pos2` in towards `pos1` until it is no further than `range` away, and give back
--- the result. Both arguments are written through, which is how the original was used.
---@param pos1 MapPosition
---@param pos2 MapPosition
---@param range number
---@return MapPosition pos1
function geometry.max_range(pos1, pos2, range)
    local separation = geometry.distance(pos1, pos2)
    pos2.x = pos2.x - pos1.x
    pos2.y = pos2.y - pos1.y
    pos2.x = pos2.x * math.min(1, range / separation)
    pos2.y = pos2.y * math.min(1, range / separation)
    pos1.x = pos1.x + pos2.x
    pos1.y = pos1.y + pos2.y
    return pos1
end

return geometry
