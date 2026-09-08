--- Who is being driven, and who should be.
---
--- The mod only does anything to a vehicle it has on its books, so how a vehicle gets
--- onto them -- and off again -- is the whole of its bookkeeping.
local geometry = require("lib.geometry")

local tracking = {}

--- Vehicles another mod is already moving itself, which this mod must not touch. Two
--- mods writing speed and position to the same entity every tick do not average out;
--- they overwrite each other, and the vehicle stutters or refuses to go anywhere.
---
--- Naming the prototypes is the only way to know. Nothing on a vehicle says whether some
--- other mod has claimed it, and the mods that do claim one identify it by name too. So
--- each entry is tied to the mod that ships it, and a name only counts when that mod is
--- actually loaded -- a bare list rots silently when a mod renames its prototypes, and
--- would wrongly exclude an unrelated vehicle that happened to share a name.
--- AircraftRealism keeps no fixed list of planes: other mods register theirs with it at
--- the data stage, and it carries the registry into the control stage by serialising it
--- into the order field of a run of prototypes. Reading the same registry is the only way
--- to know which planes it has taken charge of, and it is how the mod itself does it.
---@param entity_prototypes table<string, any>
---@param decode function? the deserialiser, for tests; the game's serpent by default
---@return table<string, boolean>
function tracking.aircraft_realism_planes(entity_prototypes, decode)
	decode = decode or (serpent and serpent.load)
	if not decode then return {} end
	local serialised, index = "", 0
	while true do
		local holder = entity_prototypes["aircraft-realism-plane-properties-" .. index]
		if not holder then break end
		serialised = serialised .. (holder.order or "")
		index = index + 1
	end
	if serialised == "" then return {} end
	-- serpent.load answers with its own success flag before the value, so through pcall
	-- there are three results to unpack, not two
	local called, loaded, registry = pcall(decode, serialised)
	if not called or not loaded or type(registry) ~= "table" then return {} end
	local names = {}
	for name in pairs(registry.grounded or {}) do names[name] = true end
	for name in pairs(registry.airborne or {}) do names[name] = true end
	return names
end

--- Vehicles another mod is already moving itself, which this mod must not touch. Two
--- mods writing speed and position to the same entity every tick do not average out;
--- they overwrite each other, and the vehicle stutters or refuses to go anywhere.
---
--- Naming the prototypes is the only way to know. Nothing on a vehicle says whether some
--- other mod has claimed it, and the mods that do claim one identify it by name too. So
--- each entry is tied to the mod that ships it, and a name only counts when that mod is
--- actually loaded -- a bare list rots silently when a mod renames its prototypes, and
--- would wrongly exclude an unrelated vehicle that happened to share a name. That last
--- part is not hypothetical here: WH40k Titans calls its vehicles things like "reaver"
--- and "warlord".
---
--- Found by reading the control stage of the two hundred most downloaded vehicle mods on
--- the portal for writes to speed, orientation and riding_state. Mods that steer whatever
--- the player happens to be driving -- VehicleSnap, Pavement Drive Assist, autodrive,
--- RoboTank, AAI Programmable Vehicles, Cardinal -- are deliberately not here: they claim
--- no vehicles of their own, so there is nothing to name, and excluding what they touch
--- would mean excluding the car.
local FOREIGN = {
	-- Sparr's raven mod, which flies its birds itself
	["raven2"] = { names = { "raven2-1", "raven2-2", "raven2-shadow" } },

	-- Hovercrafts runs a full drift model of its own on these four, teleporting them and
	-- setting their speed every tick
	["Hovercrafts"] = { names = {
		"hovercraft", "electric-hovercraft", "missile-hovercraft", "laser-hovercraft",
	} },

	-- HelicopterRevival flies its helicopters from script, down to writing the pilot's
	-- riding_state. It builds its prototype names from a per-helicopter prefix, so there
	-- is no fixed list to copy: the base a pilot actually sits in is <prefix>heli-entity-_-,
	-- and <prefix>helicopter is the placement entity it swaps out on build.
	["HelicopterRevival"] = { patterns = { "entity%-_%-$", "helicopter$" } },

	-- Laser Tanks carries the same drift model as Hovercrafts, on these two
	["laser_tanks"] = { names = { "lasercar", "lasertank" } },

	-- WH40k Titans damps its titans' speed itself every tick. Its aircraft supplier is a
	-- car too, but nothing in the mod moves it, so it keeps the physics.
	["WH40k-Titans"] = { names = {
		"wh40k-titan-warhound", "wh40k-titan-direwolf", "wh40k-titan-reaver",
		"wh40k-titan-warbringer", "wh40k-titan-warlord", "wh40k-titan-warmaster",
		"wh40k-titan-imperator", "wh40k-titan-warmonger",
	} },

	-- The C5 Galaxy flies itself: a stall floor on its speed, an autopilot, and a swap
	-- between the grounded and flying prototypes at takeoff
	["c5-galaxy"] = { names = { "c5-galaxy-grounded", "c5-galaxy-flying" } },

	-- AircraftRealism runs takeoff, landing, stall and overspeed on whichever planes have
	-- been registered with it, which is not something a fixed list can say
	["AircraftRealism"] = { lookup = function(entity_prototypes)
		return tracking.aircraft_realism_planes(entity_prototypes)
	end },
}

--- The vehicle names other mods own, out of everything installed.
---
--- Pure, and separate from the caching below, so it can be checked against a made-up
--- mod list without a game running.
---@param active_mods table<string, string> what script.active_mods holds
---@param entity_prototypes table<string, any> what prototypes.entity holds
---@return table<string, boolean>
function tracking.foreign_vehicles(active_mods, entity_prototypes)
	local foreign = {}
	for mod, claim in pairs(FOREIGN) do
		if active_mods[mod] then
			for _, name in pairs(claim.names or {}) do
				foreign[name] = true
			end
			for _, pattern in pairs(claim.patterns or {}) do
				for name in pairs(entity_prototypes) do
					if name:find(pattern) then foreign[name] = true end
				end
			end
			if claim.lookup then
				for name in pairs(claim.lookup(entity_prototypes)) do
					foreign[name] = true
				end
			end
		end
	end
	return foreign
end

local foreign = nil

--- Whether another mod owns this vehicle's movement. What is installed cannot change
--- while a game is running, so the answer is worked out once and kept.
---@param entity_name string
---@return boolean
function tracking.excluded(entity_name)
	foreign = foreign or tracking.foreign_vehicles(script.active_mods, prototypes.entity)
	return foreign[entity_name] or false
end


--- Start tracking a car, a tick after somebody got into it. The wait is deliberate: at
--- the moment the event fires the vehicle has not moved yet, and the physics wants a
--- position and speed to work from.
---@param entity LuaEntity
function tracking.start(entity)
	storage.cars[entity.unit_number] = {
		entity = entity,
		drift = {x=0,y=0},
		position = entity.position,
		idle_ticks = 0,
		orientation = entity.orientation,
		last_pos = entity.position,
		last_speed = entity.speed,
	}
	if entity.speed ~= 0 then
		storage.cars[entity.unit_number].drift = geometry.projection(entity.orientation, entity.speed)
	end
end


--- Everything somebody is already sitting in. on_player_driving_changed_state only fires
--- when somebody gets in or out, so a player who was already at the wheel when this mod
--- arrived -- a fresh install, or the mod switched back on -- would never be picked up at
--- all, and the physics would simply not happen until they got out and back in.
function tracking.adopt()
	for _, player in pairs(game.players) do
		local vehicle = player.vehicle
		if vehicle and vehicle.valid and vehicle.type == "car"
			and not tracking.excluded(vehicle.name) and vehicle.get_driver() then
			if vehicle.name:find("tank") then
				storage.tanks[vehicle.unit_number] = { entity = vehicle }
			else
				tracking.start(vehicle)
			end
		end
	end
end


--- Ground, boat or aircraft, worked out from what the vehicle collides with. Nothing in
--- the game says which a vehicle is, but the collision mask has to say where it can go,
--- and that is the same question:
---
---   collides with ground   it can only be on water, so it is a boat
---   collides with the player layer, as water tiles do, so it cannot cross water: ground
---   collides with neither  nothing stops it, so it is flying
---
--- Checked against what the popular vehicle mods actually ship: Cargo Ships' indep-boat
--- and AAI's ironclad come out as boats, Aircraft's eight planes and Hovercrafts' four
--- craft as flying, and the car and tank as ground. Lex's Aircraft is a spider-vehicle
--- rather than a car, so nothing here sees it at all.
---@param entity_name string
---@return "ground"|"boat"|"flying"
function tracking.kind(entity_name)
	storage.vehicle_kind = storage.vehicle_kind or {}
	local known = storage.vehicle_kind[entity_name]
	if not known then
		local layers = prototypes.entity[entity_name].collision_mask.layers
		if layers.ground_tile then
			known = "boat"
		elseif layers.player then
			known = "ground"
		else
			known = "flying"
		end
		storage.vehicle_kind[entity_name] = known
	end
	return known
end

--- How each kind handles, as multiples of what a car does.
---
--- `accelerating` and `braking` scale the speed the game gives or takes each tick, so a
--- tenth means a tenth of the acceleration a car would have had. `drift` is how much more
--- readily it slides: a car corrects a tenth and a bit of its drift towards the way it is
--- pointing every tick, and a drift of 4 means it corrects a quarter as much, so it holds
--- its old line four times as stubbornly. `rotate` scales how fast the nose comes round.
---
--- A car is the baseline and is left exactly as it was.
tracking.HANDLING = {
	ground = { accelerating = 1,    braking = 1,    drift = 1,  rotate = 1 },
	boat   = { accelerating = 0.25, braking = 0.25, drift = 4,  rotate = 0.125 },
	flying = { accelerating = 0.1,  braking = 0.1,  drift = 10, rotate = 0.25 },
}

--- What a car keeps of its drift each tick, rolling and on the brakes. Everything else is
--- expressed against these.
tracking.CAR_DRIFT = { rolling = 0.865, braking = 0.95 }

--- The share of its drift a vehicle carries into the next tick.
---
--- The car's figure says it corrects 13.5% of its drift towards its heading each tick
--- when rolling. Sliding `drift` times as much means correcting `drift` times less, so
--- the correction is divided and the rest is what it keeps.
---@param kind "ground"|"boat"|"flying"
---@param braking boolean
---@return number
function tracking.drift_multiplier(kind, braking)
	local car = tracking.CAR_DRIFT[braking and "braking" or "rolling"]
	return 1 - (1 - car) / tracking.HANDLING[kind].drift
end

--- Would this vehicle be sitting on ground it cannot be on, if it were put here?
---
--- The drift moves a vehicle by teleporting it, and a teleport asks nothing about where
--- it is going. A boat cannot be on land, so a boat drifting shorewards would be put on
--- the beach and stick there, unable to move because every direction out is also land.
--- The same question keeps a car out of the water.
---@param entity LuaEntity
---@param position MapPosition
---@return boolean
function tracking.aground(entity, position)
	local box = entity.prototype.collision_box
	local mask = entity.prototype.collision_mask.layers
	local surface = entity.surface
	for x = math.floor(position.x + box.left_top.x),
	        math.floor(position.x + box.right_bottom.x) do
		for y = math.floor(position.y + box.left_top.y),
		        math.floor(position.y + box.right_bottom.y) do
			for layer in pairs(surface.get_tile(x, y).prototype.collision_mask.layers) do
				if mask[layer] then return true end
			end
		end
	end
	return false
end

--- Drop a registration that has not happened yet, for somebody who got in and straight
--- back out again. Without it the car stays on the books with nobody in it, for good.
---@param entity LuaEntity
function tracking.cancel_pending(entity)
	for _, queued in pairs(storage.entering) do
		for index = #queued, 1, -1 do
			if queued[index] == entity then table.remove(queued, index) end
		end
	end
end

return tracking
