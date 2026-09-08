--- Somewhere to drive, and a switch to turn the physics off with.
---
--- The mod only acts on vehicles it has on its books, so switching it off for a vehicle
--- means taking that vehicle off them: what is left is the game's own physics, on the
--- same vehicle, with the same fuel and the same ground under it. Switching it back on
--- puts it back.
---
--- Two ways to flip it, because comparing is easier when it costs nothing: press N, or
--- get out and get back in. Either way it says which you are on.
local tracking = require("lib.tracking")

local sandbox = {}

--- Where everything goes. Fixed coordinates rather than relative to the player, and the
--- player is brought to them: the freeplay scenario moves the player about after it
--- creates them, so anything placed relative to where they happen to be standing ends up
--- somewhere else entirely.
local ORIGIN = { x = 0, y = 0 }
local SHORE = 45          -- water from here east
local PIER_END = 52       -- walkable out to here, so the boat can be reached
--- A boat collides with ground, so it has to float clear of the pier or it cannot move at
--- all: the pier's last tile ends at 53, and the boat's hull is 1.4 wide, so 53.8 puts its
--- western edge at 53.1 and nothing of it over land. Boarding reaches about a tile and a
--- half, measured, and the pier edge is within that.
local BOAT_X = 53.8

--- Freeplay drops a crashed ship at the spawn point, scatters wreckage around it, hands
--- out starting items and plays an intro that moves the player. All of it gets in the way
--- of a driving test, and all of it can be switched off before it happens.
function sandbox.on_init()
    if remote.interfaces["freeplay"] then
        if remote.interfaces["freeplay"]["set_disable_crashsite"] then
            remote.call("freeplay", "set_disable_crashsite", true)
        end
        if remote.interfaces["freeplay"]["set_skip_intro"] then
            remote.call("freeplay", "set_skip_intro", true)
        end
        if remote.interfaces["freeplay"]["set_created_items"] then
            remote.call("freeplay", "set_created_items", {})
        end
    end
end


local MODDED_COLOUR = { r = 0.3, g = 1, b = 0.4 }
local STOCK_COLOUR = { r = 1, g = 0.55, b = 0.2 }

local function state()
    storage.sandbox = storage.sandbox or { modded = true, labels = {} }
    return storage.sandbox
end

--- Put the vehicle on or off the mod's books to match the switch
local function apply(vehicle)
    if not (vehicle and vehicle.valid and vehicle.type == "car") then return end
    if state().modded then
        if not (storage.cars[vehicle.unit_number] or storage.tanks[vehicle.unit_number]) then
            if vehicle.name:find("tank") then
                storage.tanks[vehicle.unit_number] = { entity = vehicle }
            else
                tracking.start(vehicle)
            end
        end
    else
        storage.cars[vehicle.unit_number] = nil
        storage.tanks[vehicle.unit_number] = nil
        -- and the registration waiting a tick behind, or the mod puts the vehicle
        -- straight back on its books and the switch reads the opposite of the truth
        tracking.cancel_pending(vehicle)
    end
end

--- The label that floats over whatever the player is driving
local function show(player)
    local sb = state()
    for _, id in pairs(sb.labels) do
        if id.valid then id.destroy() end
    end
    sb.labels = {}

    local vehicle = player.vehicle
    local modded = sb.modded
    local text = modded and "VEHICLE PHYSICS: ON" or "VEHICLE PHYSICS: OFF (stock game)"
    if vehicle then
        sb.labels[#sb.labels + 1] = rendering.draw_text{
            text = text,
            surface = vehicle.surface,
            target = { entity = vehicle, offset = { 0, -2.6 } },
            color = modded and MODDED_COLOUR or STOCK_COLOUR,
            scale = 1.6,
            alignment = "center",
        }
        sb.labels[#sb.labels + 1] = rendering.draw_text{
            text = vehicle.name .. "  (" .. tracking.kind(vehicle.name) .. ")",
            surface = vehicle.surface,
            target = { entity = vehicle, offset = { 0, -1.9 } },
            color = { r = 0.85, g = 0.85, b = 0.85 },
            scale = 1.1,
            alignment = "center",
        }
    end

    local gui = player.gui.top
    if gui.vp_sandbox then gui.vp_sandbox.destroy() end
    local label = gui.add{ type = "label", name = "vp_sandbox", caption = text }
    label.style.font = "default-large-bold"
    label.style.font_color = modded and MODDED_COLOUR or STOCK_COLOUR
end

--- Out of the boat and back on dry land. There is no other way out of one: leaving a
--- vehicle puts the player down beside it, and beside a boat is water, which the game
--- refuses -- so somebody who sails out into open water is aboard for good.
---@param player LuaPlayer
function sandbox.ashore(player)
    local vehicle = player.vehicle
    if vehicle and vehicle.valid and tracking.kind(vehicle.name) == "boat" then
        -- The game will not put a person down in water, and a boat in open water has
        -- nothing but water around it, so there is no way out of one by any means the
        -- game offers. The boat is run up the beach far enough that its hull overlaps
        -- dry land -- a teleport asks nothing about where it is going, which is a
        -- nuisance everywhere else and useful here -- the player steps off onto that
        -- land, and the boat is put back at its mooring behind them.
        vehicle.speed = 0
        vehicle.teleport({ SHORE - 0.5, ORIGIN.y + 20 })
        player.driving = false
        if vehicle.valid then vehicle.teleport({ BOAT_X, ORIGIN.y }) end
    else
        player.driving = false
    end

    if not player.driving then
        player.teleport({ PIER_END - 1, ORIGIN.y }, player.surface)
        player.print("[color=cyan]Back on the pier; the boat is at its mooring.[/color]")
    end
    show(player)
end

--- Set the switch and make it so. Public so that a fixture can throw it the same way the
--- hotkey does, rather than reaching past it and reimplementing what it means.
---@param player LuaPlayer
---@param modded boolean
function sandbox.set(player, modded)
    state().modded = modded
    apply(player.vehicle)
    show(player)
end

local function flip(player, why)
    local sb = state()
    sandbox.set(player, not sb.modded)
    player.create_local_flying_text{
        text = (sb.modded and "physics ON" or "physics OFF") .. " (" .. why .. ")",
        create_at_cursor = false,
        position = player.position,
        color = sb.modded and MODDED_COLOUR or STOCK_COLOUR,
    }
    player.print((sb.modded and "[color=green]Vehicle Physics ON[/color]"
                             or "[color=orange]Vehicle Physics OFF, stock game[/color]")
                 .. " -- " .. why)
end

function sandbox.build(player)
    local surface = player.surface
    -- out of whatever they are sitting in first: teleporting a seated player moves the
    -- vehicle or fails outright, and either way they do not end up where this puts them
    if player.driving then
        local previous = player.vehicle
        player.driving = false
        if player.driving and previous and previous.valid then previous.destroy() end
    end
    surface.request_to_generate_chunks(ORIGIN, 5)
    surface.force_generate_chunk_requests()

    -- paved to the west, stripes of paving and sand, grass, then open water
    local tiles = {}
    for x = -90, 90 do
        for y = -90, 90 do
            local name
            if x < -20 then name = "refined-concrete"
            elseif x < 30 then name = (math.floor(y / 14) % 2 == 0) and "refined-concrete"
                                       or "sand-1"
            elseif x < SHORE then name = "grass-1"
            else name = "water" end
            -- A pier, so the boat is something you can walk up to. One tile wide: a
            -- broad one is a wall to catch the hull on, and a boat that snags on it has
            -- to be wiggled off.
            if x >= SHORE and x <= PIER_END and y == 0 then name = "grass-1" end
            tiles[#tiles + 1] = { name = name, position = { x, y } }
        end
    end
    surface.set_tiles(tiles)

    -- everything, not a list of types: the scenario's crashed ship, its wreckage, the
    -- fires around it and whatever it dropped are all in the way of a driving test
    for _, entity in pairs(surface.find_entities{ { -90, -90 }, { 90, 90 } }) do
        if entity.valid and entity.type ~= "character" then entity.destroy() end
    end

    local function place(name, x, y)
        local vehicle = surface.create_entity{ name = name, position = { x, y },
                                               force = "player" }
        if vehicle then vehicle.insert{ name = "nuclear-fuel", count = 5 } end
        return vehicle
    end
    place("car", ORIGIN.x + 6, ORIGIN.y)
    place("tank", ORIGIN.x + 6, ORIGIN.y + 8)
    place("vp-tests-plane", ORIGIN.x + 6, ORIGIN.y - 8)
    place("vp-tests-boat", BOAT_X, ORIGIN.y)

    player.teleport(ORIGIN, surface)
    player.cheat_mode = true
    local inventory = player.get_main_inventory()
    if inventory then inventory.insert{ name = "nuclear-fuel", count = 50 } end

    player.print("[color=cyan]Vehicle Physics sandbox[/color]")
    player.print("A car, a tank and an aircraft are six tiles east of you.")
    player.print("Follow the pier east to the water for the boat.")
    player.print("Press [color=yellow]N[/color] to switch the physics on and off, or just "
                 .. "get out and back in -- either flips it.")
    player.print("Press [color=yellow]B[/color] to get out of the boat: there is no water "
                 .. "to step out onto, so the game will not let you leave it otherwise.")
    show(player)
end

--- Called from the mod's own driving handler rather than registered here. A mod gets one
--- handler per event, so registering for on_player_driving_changed_state would replace the
--- mod's own and quietly turn off the very thing being tested.
---@param event EventData.on_player_driving_changed_state
function sandbox.on_driving_changed(event)
    local player = game.players[event.player_index]
    if player.vehicle then
        -- flipping on the way in means one lap each way tells you everything
        flip(player, "got in")
    else
        show(player)
    end
end

function sandbox.register()
    script.on_event("vp-tests-toggle-physics", function(event)
        flip(game.players[event.player_index], "hotkey")
    end)

    script.on_event("vp-tests-ashore", function(event)
        sandbox.ashore(game.players[event.player_index])
    end)

    --- Built a tick after the player appears rather than the moment they do. The scenario
    --- moves them to the spawn point after on_player_created, so anything positioned
    --- during that event is positioned relative to somewhere they are about to leave.
    --- on_nth_tick rather than on_tick, which the mod itself owns.
    script.on_event(defines.events.on_player_created, function()
        -- a second in, long after the scenario has finished moving anybody
        script.on_nth_tick(60, function()
            script.on_nth_tick(60, nil)
            local player = game.players[1]
            if player then sandbox.build(player) end
        end)
    end)
end

return sandbox
