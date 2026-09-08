local geometry = require("lib.geometry")
local tracking = require("lib.tracking")

--- A place to try the mod out by hand, present only when the test prototypes are and the
--- suite is not running. It is called into from the handlers below rather than
--- registering its own, since a mod gets one handler per event.
local sandbox = nil
if script.active_mods["vp-tests"] and not script.active_mods["factorio-test"] then
	sandbox = require("test.sandbox")
	sandbox.register()
end

script.on_event(defines.events.on_player_driving_changed_state, function(event)
if event.entity and event.entity.type == "car" and not tracking.exclusions[event.entity.name] then
	if not event.entity.get_driver() then
		storage.cars[event.entity.unit_number] = nil
		storage.tanks[event.entity.unit_number] = nil
		-- and drop any registration still waiting its turn, or getting in and straight
		-- back out again leaves the car on the books with nobody in it, for good
		tracking.cancel_pending(event.entity)
	elseif not storage.cars[event.entity.unit_number] then
		if event.entity.name:find("tank") then
			storage.tanks[event.entity.unit_number] = {entity = event.entity}
		else
			-- The entity itself is remembered, and the work is done next tick in on_tick.
			-- This used to remember a function to call instead, which a save cannot hold:
			-- anybody saving in the one tick between getting into a car and the next took
			-- "cannot serialise lua functions" and lost the game.
			if not storage.entering[event.tick+1] then
				storage.entering[event.tick+1] = {}
			end
			table.insert(storage.entering[event.tick+1], event.entity)
		end
	end
end
if sandbox then sandbox.on_driving_changed(event) end
end)


function make_tire_marks(surface,position,speed,unit_number)
	speed = math.max(0.4, math.min(0.8, speed^0.4*1.2))*0.7
	local tick = game.tick
	local tilename = surface.get_tile(position.x,position.y).name
	if tilename:find("sand") or
	   tilename:find("desert") or
	   tilename:find("dirt") or
	   tilename:find("landfill") or
	   tilename:find("grass") then
		surface.create_entity{name = "drifting-tire-marks-faded", position = position}
		if 	(storage.geigers[unit_number] or 0)+12  < tick then
			local volume = math.max(0.2, math.min(0.8, speed^0.4*1.2))*0.75
			--local rnd = math.ceil(math.random()*2.99999+0.000001)
			--local rnd = math.floor(math.random()*1.99)
			storage.geigers[unit_number] = tick
			
			surface.play_sound({path = "vehphy-dirt", volume_modifier =volume, position = position})
			
		end
	else
		surface.create_entity{name = "drifting-tire-marks", position = position}
		if 	(storage.geigers[unit_number] or 0)+12  < tick then
			local rnd = math.ceil(math.random()*2.99999+0.000001)
			--local rnd = math.floor(math.random()*1.99)
			storage.geigers[unit_number] = tick
			
			surface.play_sound({path = "vehphy-squeel-"..rnd, volume_modifier =speed, position = position})
			
		end
	end
end

	--local distance = geometry.distance({x=0,y=0},coords)
	--local temp_x = coords.x/distance
	--local temp_y =  coords.y/distance
	--temp_x = math.asin(temp_x)/math.pi/2
	--temp_y =   math.asin(temp_y)/math.pi/2
	--game.print("x = "..temp_x)
	--game.print("y = "..temp_y-0.75)
--end
	--local temp_x = math.sin((orientation+0)*2*math.pi)*distance
	--local temp_y =  math.sin((orientation+0.75)*2*math.pi)*distance
script.on_event(defines.events.on_tick, function(event)
	for unit_number, tbl in pairs(storage.tanks) do
		if tbl.entity and tbl.entity.valid then
			local speed = tbl.entity.speed
			if math.abs(speed)>0.08 and event.tick % math.min(10,math.floor(1/speed*2)) ==0 or math.abs(speed)<0.08 and tbl.entity.riding_state.direction ~= defines.riding.direction.straight and event.tick %5 == 1 then --not really accurate but good enough
				--game.print(game.tick)
				local pos = tbl.entity.position
				local tilename = tbl.entity.surface.get_tile(pos.x,pos.y).name
				if tilename:find("sand") or tilename:find("desert") or tilename:find("dirt") then
				--if concrete_tiles == 0 then-- (drift_x^2+drift_y^2)^0.5 > required_drift*4.5 then
					tbl.entity.surface.create_trivial_smoke{name="hover-smoke", position={pos.x,pos.y+0.04}}
				end
			end
		else
			storage.tanks[unit_number] = nil
		end
	end
	for unit_number, tbl in pairs(storage.cars) do
		--game.print(unit_number)
		if tbl.entity and tbl.entity.valid then
			local speed = tbl.entity.speed
			-- Give back only the share of this tick's acceleration or braking that this
			-- kind is allowed. An aircraft gets a tenth of a car's, so it takes ten times
			-- as long to wind up and to wind down.
			local scale = tracking.HANDLING[tracking.kind(tbl.entity.name)]
			local was = tbl.last_speed or 0
			local change = speed - was
			if change > 0 and math.abs(speed) > math.abs(was) and scale.accelerating ~= 1 then
				speed = was + change * scale.accelerating
				tbl.entity.speed = speed
			elseif change ~= 0 and math.abs(speed) < math.abs(was) and scale.braking ~= 1 then
				speed = was + change * scale.braking
				tbl.entity.speed = speed
			end
			if speed == 0 and tbl.last_speed ~= 0 then
				tbl.entity.teleport(tbl.last_pos or tbl.entity.position)
				tbl.position = tbl.last_pos
				tbl.drift ={x=0,y=0}
			end
			
			local pos = tbl.entity.position
			--local temp = {x = pos.x, y = pos.y}
			
			if speed==0 then 
				tbl.idle_ticks = tbl.idle_ticks + 1
			else
				tbl.idle_ticks = 0
			end
			if tbl.idle_ticks < 50 then
				local surroundings = #tbl.entity.surface.find_entities_filtered {area = {{pos.x-1,pos.y-1},{pos.x+1,pos.y+1}}}
			--if speed ~=0 or surroundings == 1 then
				local movement_x = pos.x-tbl.position.x
				local movement_y = pos.y-tbl.position.y
				local drift_x = pos.x-tbl.position.x
				local drift_y = pos.y-tbl.position.y
				local kind = tracking.kind(tbl.entity.name)
				local is_braking = tbl.entity.riding_state.acceleration == defines.riding.acceleration.braking
				local entity_orientation = tbl.entity.orientation
				local handling = tracking.HANDLING[kind]
				local drifting_multiplier = tracking.drift_multiplier(kind, is_braking)
				drift_x = movement_x*(1-drifting_multiplier)+tbl.drift.x*drifting_multiplier
				drift_y = movement_y*(1-drifting_multiplier)+tbl.drift.y*drifting_multiplier
				--if (tbl.drifting or 1000) < 3 then
				--	new_pos = {x=tbl.position.x+movement_x*(1-tbl.drifting*0.3) + tbl.drift.x*(tbl.drifting*0.3),y=tbl.position.y+movement_y*(1-tbl.drifting*0.3) + tbl.drift.y*(tbl.drifting*0.3)}
				--end
				
				local concrete_tiles = 0
				local required_drift = 0.001
				local make_no_tire_marks = false
				if kind == "ground" then
					local tiles = tbl.entity.surface.find_tiles_filtered{position=tbl.entity.position, radius = 1.5}
					for a,b in pairs(tiles) do
						if b.prototype.vehicle_friction_modifier <=0.9 then
							concrete_tiles = concrete_tiles + 1
						end						
					end
					if concrete_tiles >=1 then
						--required_drift = 0.1
						--game.print(game.tick.."concrete")
						drifting_multiplier = math.min(0.95,math.max(0,0.6+math.max(0,0.7-math.abs(speed))*0.5-tbl.idle_ticks*0.02))
						--game.print(tbl.entity.speed) --150 = 0.69
						if is_braking then
							
							local orientation_difference
							if speed >= 0 then
								orientation_difference = math.abs(geometry.orientation_from_coords({x=tbl.drift.x, y = tbl.drift.y}) - entity_orientation)
							else
								orientation_difference = math.abs(geometry.orientation_from_coords({x=tbl.drift.x, y = tbl.drift.y}) - (entity_orientation+0.5)%1) 
							end
							if orientation_difference > 0.971 then
								orientation_difference = -(orientation_difference-1)
								if speed < 0 then
									speed = math.min(0,speed + 0.003)
									tbl.entity.speed = speed
								elseif speed > 0 then
									speed = math.max(0,speed - 0.003)
									tbl.entity.speed = speed
								end
								make_no_tire_marks = true
								--game.print(orientation_difference)
								--drifting_multiplier = math.min(0.95,math.max(0,0.6+math.max(0,0.7-tbl.entity.speed)*0.5-tbl.idle_ticks*0.02+speed*0.45))*orientation_difference*10
							elseif orientation_difference < 0.029 then
								tbl.entity.speed = speed -0.003
								make_no_tire_marks = true
								--drifting_multiplier = math.min(0.95,math.max(0,0.6+math.max(0,0.7-tbl.entity.speed)*0.5-tbl.idle_ticks*0.02+speed*0.45))*orientation_difference*10
								--game.print(orientation_difference)
							else
								drifting_multiplier = math.min(0.95,math.max(0,0.6+math.max(0,0.7-math.abs(speed))*0.5-tbl.idle_ticks*0.02+math.abs(speed)*0.45))
							end
						end
						drift_x = movement_x*(1-drifting_multiplier)+tbl.drift.x*drifting_multiplier
						drift_y = movement_y*(1-drifting_multiplier)+tbl.drift.y*drifting_multiplier

					end
				end
				if not is_braking then
					local manuverability = math.max(0.4,0.2 + 0.9 - math.abs(speed) / 1.5)
						* handling.rotate
					--game.print("manuver: "..manuverability)
					local orientation_change = entity_orientation - tbl.orientation
					if orientation_change < -0.5 then
						orientation_change = orientation_change +1
					elseif orientation_change > 0.5 then
						orientation_change = orientation_change -1
					end
					entity_orientation = entity_orientation - orientation_change * (1-manuverability)
					tbl.entity.orientation = entity_orientation
					tbl.orientation = entity_orientation
				else
					if kind == "ground" then
						if concrete_tiles >=1 then
							local manuverability = math.max(0.4,0.2 + 0.9 - math.abs(speed) / 3)
								* handling.rotate
							--game.print("manuver: "..manuverability)
							local orientation_change = entity_orientation - tbl.orientation
							if orientation_change < -0.5 then
								orientation_change = orientation_change +1
							elseif orientation_change > 0.5 then
								orientation_change = orientation_change -1
							end
							entity_orientation = entity_orientation - orientation_change * (1-manuverability)
							tbl.entity.orientation = entity_orientation
						end
						if not make_no_tire_marks then
							local temp_pos = {x = pos.x+0.05, y = pos.y + 0.1}
							local temp_last_pos = {x = tbl.last_pos.x+0.05, y = tbl.last_pos.y + 0.1}
							local distance_to_last = geometry.distance(tbl.last_pos,pos)
							local surface = tbl.entity.surface
							if distance_to_last > 0.35 then
								make_tire_marks(surface, geometry.projection((entity_orientation+0.4)%1,1.2, {x=(pos.x+temp_last_pos.x*2)/3,y=(temp_pos.y+temp_last_pos.y*2)/3}),speed,unit_number)
								make_tire_marks(surface, geometry.projection((entity_orientation+0.6)%1,1.2, {x=(pos.x+temp_last_pos.x*2)/3,y=(temp_pos.y+temp_last_pos.y*2)/3}),speed,unit_number)
								make_tire_marks(surface, geometry.projection((entity_orientation+0.4)%1,1.2, {x=(pos.x*2+temp_last_pos.x)/3,y=(temp_pos.y*2+temp_last_pos.y)/3}),speed,unit_number)
								make_tire_marks(surface, geometry.projection((entity_orientation+0.6)%1,1.2, {x=(pos.x*2+temp_last_pos.x)/3,y=(temp_pos.y*2+temp_last_pos.y)/3}),speed,unit_number)
								--game.print(geometry.distance(tbl.last_pos,pos))
							elseif distance_to_last > 0.2 then
								make_tire_marks(surface, geometry.projection((entity_orientation+0.4)%1,1.2, {x=(pos.x+temp_last_pos.x)/2,y=(temp_pos.y+temp_last_pos.y+0.1)/2}),speed,unit_number)
								make_tire_marks(surface, geometry.projection((entity_orientation+0.6)%1,1.2, {x=(pos.x+temp_last_pos.x)/2,y=(temp_pos.y+temp_last_pos.y+0.1)/2}),speed,unit_number)
								--game.print(geometry.distance(tbl.last_pos,pos))
							end
							if distance_to_last > 0.05 then
								make_tire_marks(surface, geometry.projection((entity_orientation+0.4)%1,1.2, temp_pos),speed,unit_number)
								make_tire_marks(surface, geometry.projection((entity_orientation+0.6)%1,1.2, temp_pos),speed,unit_number)
							end
						end
					end
					tbl.orientation = entity_orientation
				end
				--game.print("drift: "..drifting_multiplier)
				tbl.last_pos = pos
				
				if (drift_x^2+drift_y^2)^0.5 > required_drift then
					
					local new_pos = {x=tbl.position.x+drift_x,y=tbl.position.y+drift_y}
					-- Sliding sideways scrubs speed off, in proportion to how far the
					-- drift is carrying the vehicle. That is tyres biting, so it is
					-- divided by how much this kind slides: a car scrubs hard, an
					-- aircraft has nothing to bite on and barely scrubs at all. Without
					-- the division a kind that drifts ten times as much also scrubbed ten
					-- times as hard and slammed to a stop out of a slide.
					local scrub = geometry.distance(pos, new_pos) * 0.01 / handling.drift
					if speed > 0 then
						speed = math.max(0, speed - scrub)
						tbl.entity.speed = speed
					elseif speed < 0 then
						speed = math.min(0, speed + scrub)
						tbl.entity.speed = speed
					end
					--game.print(-geometry.distance(pos, new_pos)*0.01)
					--game.print(geometry.distance(pos, new_pos))
					tbl.drifting = (tbl.drifting or 0) + 1
					--game.print(game.tick)
					if kind == "ground" and event.tick % 4==2 and concrete_tiles == 0 then-- (drift_x^2+drift_y^2)^0.5 > required_drift*4.5 then
						--game.print("smoke"..game.tick)
						tbl.entity.surface.create_trivial_smoke{name="hover-smoke", position=tbl.entity.position}
					end
					
					--local collision_masks = {}
					--for mask in pairs(tbl.entity.prototype.collision_mask) do
					--	table.insert(collision_masks,mask)
	                --
					--end
					--local collisions = tbl.entity.surface.find_entities_filtered{position=new_pos, collision_mask= collision_masks}
					--if #collisions ==0 or #collisions ==1 and collisions[1].unit_number ==tbl.entity.unit_number then
					--[[
					tbl.entity.teleport(-5,-5)
					local cliffs = tbl.entity.surface.find_entities_filtered { name = "cliff", area = {{new_pos.x-1.15,new_pos.y-1.15},{new_pos.x+1.15,new_pos.y+1.15}}}
					--local rocks = tbl.entity.surface.find_entities_filtered { type = "simple-entity", area = {{new_pos.x-1,new_pos.y-1},{new_pos.x+1,new_pos.y+1}}}
					if #cliffs >0 then
						local noncolliding = tbl.entity.surface.find_non_colliding_position("hovercraft-collision", new_pos, 0.1, 0.03)
						if noncolliding and geometry.distance(noncolliding,new_pos)<0.04 then
							tbl.entity.teleport(noncolliding)
							tbl.idle_ticks = 120
						else
							tbl.entity.teleport(5,5)
							tbl.drift = {x=0,y=0}
							tbl.idle_ticks = 120
						end
					else
						if tbl.entity.surface.can_place_entity{name="hovercraft-collision",position=new_pos, direction=tbl.entity.orientation,build_check_type=defines.build_check_type.manual} then
							tbl.entity.teleport(new_pos)
						else
							tbl.entity.teleport(5,5)
						end
					end --]]
					-- The drift is applied by teleporting, and a teleport asks nothing
					-- about where it is going: a boat drifting shorewards was being put
					-- on the beach, where it stuck fast because every way out was land
					-- too. Somewhere it cannot be is somewhere it does not go, and the
					-- drift that was carrying it there is spent.
					if tracking.aground(tbl.entity, new_pos) then
						tbl.drift = {x=0,y=0}
					else
						tbl.entity.teleport(new_pos)
						tbl.drift = {x=drift_x,y=drift_y}
					end
				else
					--tbl.drift = {x=movement_x*0.1+drift_x*0.9,y=movement_y*0.1+drift_y*0.9}
					tbl.drift = {x=movement_x*0.9+drift_x*0.1,y=movement_y*0.9+drift_y*0.1}
					--tbl.drift = {x=new_pos.x-tbl.position.x,y=new_pos.y-tbl.position.y}
					--if tbl.drifting then
					--tbl.entity.speed = geometry.distance({x=0,y=0},{x=drift_x, y= drift_y})
					tbl.drifting = tbl.drifting and tbl.drifting > 1 and tbl.drifting-1
					--end
				end
			else
				tbl.drift = {x=0,y=0}
				tbl.last_pos = pos
			end

			tbl.position = tbl.entity.position
			tbl.last_speed = speed
		else
			storage.cars[unit_number] = nil
		end
	end	
	if storage.entering[event.tick] then
		for _, entity in pairs(storage.entering[event.tick]) do
			if entity.valid then tracking.start(entity) end
		end
		storage.entering[event.tick] = nil
	end
end)

script.on_init(function()
	if sandbox then sandbox.on_init() end
	storage.entering = {}
	storage.cars = {}
	storage.tanks = {}
	storage.vehicle_kind = {}
	storage.geigers = {}
	storage.version = 3
	tracking.adopt()
end)
script.on_configuration_changed(function()
	if storage.version == 1 then
		storage.geigers = {}
		storage.version = 2
	end
	if storage.version == 2 then
		-- on_tick held functions to call, which is why no save could ever hold one
		storage.on_tick = nil
		storage.entering = {}
		storage.version = 3
	end
	-- the mask is now read for three answers rather than two, and 2.0 rewrote masks
	-- anyway, so nothing a previous version worked out is worth keeping
	storage.is_flycar = nil
	storage.vehicle_kind = {}
	tracking.adopt()
end)

--- vp-tests is never published, so this can never fire on a player's machine -- which
--- matters, because info.json keeps test/ out of the package.
if script.active_mods["factorio-test"] and script.active_mods["vp-tests"] then
	require("__factorio-test__/init")({
		"test.ft.driving",
		"test.ft.tracking",
		"test.ft.kinds",
		"test.ft.sandbox_check",
		"test.ft.measure",
	}, {
		load_luassert = true,
		game_speed = 100,
	})
end
