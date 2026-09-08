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

local function flip(player, why)
    local sb = state()
    sb.modded = not sb.modded
    apply(player.vehicle)
    show(player)
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
    surface.request_to_generate_chunks({ 0, 0 }, 5)
    surface.force_generate_chunk_requests()

    -- paved on the left, loose in the middle, a channel of water on the right for a boat
    local tiles = {}
    for x = -90, 90 do
        for y = -90, 90 do
            local name
            if x < -20 then name = "refined-concrete"
            elseif x < 30 then name = (math.floor(y / 14) % 2 == 0) and "refined-concrete"
                                       or "sand-1"
            elseif x < 45 then name = "grass-1"
            else name = "water" end
            tiles[#tiles + 1] = { name = name, position = { x, y } }
        end
    end
    surface.set_tiles(tiles)

    for _, entity in pairs(surface.find_entities_filtered{
        area = { { -90, -90 }, { 90, 90 } },
        type = { "tree", "simple-entity", "unit", "unit-spawner", "turret", "cliff",
                 "simple-entity-with-owner", "container", "car" } }) do
        if entity.valid then entity.destroy() end
    end

    local function place(name, x, y)
        local vehicle = surface.create_entity{ name = name, position = { x, y },
                                               force = "player" }
        if vehicle then vehicle.insert{ name = "nuclear-fuel", count = 5 } end
        return vehicle
    end
    place("car", -30, 0)
    place("tank", -30, 10)
    place("vp-tests-plane", -30, -10)
    place("vp-tests-boat", 60, 0)

    player.teleport({ -34, 0 })
    player.cheat_mode = true
    local inventory = player.get_main_inventory()
    if inventory then inventory.insert{ name = "nuclear-fuel", count = 50 } end

    player.print("[color=cyan]Vehicle Physics sandbox[/color]")
    player.print("A car, a tank, an aircraft and, out east in the water, a boat.")
    player.print("Press [color=yellow]N[/color] to switch the physics on and off, or just "
                 .. "get out and back in -- either flips it.")
    player.print("Left of x=-20 is paved. The middle is striped paving and sand. "
                 .. "Grass, then water.")
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

    script.on_event(defines.events.on_player_created, function(event)
        sandbox.build(game.players[event.player_index])
    end)
end

return sandbox
