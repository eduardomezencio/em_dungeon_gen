-- Copyright 2015 Eduardo Mezêncio

---------------
-- Constants --
---------------

local modname = "em_dungeon_gen"

local roomsize = 6
local halfrs = math.floor(roomsize / 2)
local wallarea = (roomsize + 1) * (roomsize - 1)

local pit_floors_min, pit_floors_max = 4, 8
local pit_layer_size = pit_floors_max * roomsize


----------------------
-- Helper Functions --
----------------------

local function chance(num, den)
	return (math.random(den) <= num)
end

---------------
-- Materials --
---------------

local c_air = minetest.get_content_id("air")
local c_cobble = minetest.get_content_id("default:cobble")
local c_mossycobble = minetest.get_content_id("default:mossycobble")
local c_torch = minetest.get_content_id("default:torch")
local c_bar_ns = minetest.get_content_id("xpanes:bar_5")
local c_bar_ew = minetest.get_content_id("xpanes:bar_10")

local function c_wall()
	if chance(1,2) then
		return c_cobble
	else
		return c_mossycobble
	end
end

local schematic_stairs = minetest.get_modpath(modname).."/schems/stairs.mts"

------------------
-- Change Spawn --
------------------

local spawn_x, spawn_y, spawn_z = halfrs, 1, halfrs

minetest.register_on_newplayer(function(player)
	player:setpos({x = spawn_x, y = spawn_y, z = spawn_z})
end)

minetest.register_on_respawnplayer(function(player)
	player:setpos({x = spawn_x, y = spawn_y, z = spawn_z})
	return true
end)


-------------------------
-- Map Generation Init --
-------------------------

local mapseed

minetest.register_on_mapgen_init(function(mgparams)
	if mgparams.mgname ~= "singlenode" then
		minetest.set_mapgen_params({mgname="singlenode"})
	end
	mapseed = minetest.get_mapgen_params().seed
end)

--------------------
-- Map Generation --
--------------------

minetest.register_on_generated(function(minp, maxp, blockseed)

	-- just for now, so that you can take a look from above :)
	if minp.y > 0 then return end

	local vm, emin, emax = minetest.get_mapgen_object("voxelmanip")
	local va = VoxelArea:new{MinEdge=emin, MaxEdge=emax}
	local data = vm:get_data()

	local x_step = va:index(1,0,0) - va:index(0,0,0)
	local y_step = va:index(0,1,0) - va:index(0,0,0)
	local z_step = va:index(0,0,1) - va:index(0,0,0)

	-------------------
	-- Floor/Ceiling --
	-------------------

	math.randomseed(minp.x + minp.y^2 + minp.z^3)

	for y = minp.y, maxp.y do
	if y % roomsize == 0 then
		for z = minp.z, maxp.z do
			local index = va:index(minp.x, y, z)
			for x = minp.x, maxp.x do
				data[index] = c_wall()
				index = index + x_step
			end
		end
	end
	end

	-- I'm subtracting roomsize at the end here so that each chunk also
	-- 'generates' one room outside of it. The reason is to build correctly
	-- things that are in the block borders
	local minx, miny, minz = minp.x, minp.y, minp.z
	if minx % roomsize ~= 0 then minx = minx - (minx % roomsize) - roomsize end
	if miny % roomsize ~= 0 then miny = miny - (miny % roomsize) - roomsize end
	if minz % roomsize ~= 0 then minz = minz - (minz % roomsize) - roomsize end

	------------------------------
	-- Walls, Doors and Torches --
	------------------------------

	local doors, next_door = {}, 1
	local stairs, next_stairs = {}, 1

	local function place_stuff(x, y, z, ns)

		-----------
		-- Walls --
		-----------

		if chance(3,4) then

			local xval, zval, step
			local rect = {b = math.max(minp.y, y + 1),
			              t = math.min(maxp.y, y + roomsize - 1)}

			if ns then
			        rect.l = math.max(minp.x, x)
			        rect.r = math.min(maxp.x, x + roomsize)
			        xval = rect.l
			        zval = z
			        step = x_step
			else
				rect.l = math.max(minp.z, z)
			        rect.r = math.min(maxp.z, z + roomsize)
			        xval = x
			        zval = rect.l
			        step = z_step
			end

			local wallnodes = 0
			for yval = rect.b, rect.t do
				local index = va:index(xval, yval, zval)
				for x_or_z = rect.l, rect.r do
					data[index] = c_wall()
					wallnodes = wallnodes + 1
					index = index + step
				end
			end
			-- This will hopefully ensure that the random number
			-- generator is always in the same "position" after
			-- generating the wall
			while wallnodes < wallarea do
				math.random()
				wallnodes = wallnodes + 1
			end

			-----------
			-- Doors --
			-----------

			if chance(1,2) then

				local coord = {x = x, y = y + 2, z = z}

				if ns then coord.x = coord.x + halfrs
				else coord.z = coord.z + halfrs end

				-- Portal --
				if va:contains(coord.x, coord.y, coord.z) then
					data[va:index(coord.x, coord.y, coord.z)] = c_air end
				coord.y = coord.y - 1
				if va:contains(coord.x, coord.y, coord.z) then
					data[va:index(coord.x, coord.y, coord.z)] = c_air end

				-- Door (generated later) --
				if chance(1,2) then
					doors[next_door] = {x=coord.x, y=coord.y, z=coord.z, ns=ns}
					next_door = next_door + 1
				end

			else

				if chance(1,2) then

					local c_bar
					local coord = {x = x, y = y + 2, z = z}

					if ns then
						coord.x = coord.x + halfrs
						c_bar = c_bar_ns
					else
						coord.z = coord.z + halfrs
						c_bar = c_bar_ew
					end

					-- Window --
					if va:contains(coord.x, coord.y, coord.z) then
						data[va:index(coord.x, coord.y, coord.z)] = c_bar
					end
				end
			end
		end
	end

	for y=miny, maxp.y, roomsize do
	for z=minz, maxp.z, roomsize do
	for x=minx, maxp.x, roomsize do

		math.randomseed(x + y^2 + z^3)

		-- Stairs (generated later)
		if chance(1, 128) then

			stairs[next_stairs] = {x = x, y = y, z = z,
			                       dir = math.random(0,3)}
			next_stairs = next_stairs + 1

		else

			place_stuff(x, y, z, true) -- along the x axis
			place_stuff(x, y, z, false) -- along the z axix

			-------------
			-- Torches --
			-------------

			if chance(1,8) then
				local coord = {x = x + halfrs,
					       y = y + roomsize - 1,
					       z = z + halfrs}
				if va:contains(coord.x, coord.y, coord.z) then
					data[va:index(coord.x, coord.y, coord.z)] = c_torch
				end
			end
		end
	end
	end
	end
	
	----------
	-- Pits --
	----------
	
	local block_depth = maxp.y - minp.y + 1
	local pit_layers = math.ceil(block_depth / pit_layer_size) + 2
	local first_pit_layer = minp.y - (minp.y % pit_layer_size) - pit_layer_size

	local y = first_pit_layer	
	for layer_count = 1, pit_layers do
		
		for z=minz, maxp.z, roomsize do
		for x=minx, maxp.x, roomsize do

			math.randomseed(x + y^2 + z^3)
		
			if chance(1, 128) then
				
				local start = math.random(1, pit_floors_max)
				local size = math.random(pit_floors_min, pit_floors_max)

				local yy = y + start * roomsize
				for floor_count = 1, size do
				
					-- Remove torches
					if va:contains(x + halfrs, yy - 1, z + halfrs) then
						data[va:index(x + halfrs, yy - 1, z + halfrs)] = c_air
					end
					
					if yy > maxp.y then break end
					
					if yy >= minp.y then
					for zz = math.max(minp.z, z + 1), math.min(maxp.x, z + roomsize - 1) do
						
						local startx = math.max(minp.x, x + 1)
						local index = va:index(startx, yy, zz)
						for xx = startx, math.min(maxp.x, x + roomsize - 1) do
						
							data[index] = c_air
							index = index + x_step
						end
					end
					end
					
					yy = yy + roomsize
				end
			end
		
		end
		end
		
		y = y + pit_layer_size
	end	
	

	vm:set_data(data)
	vm:set_lighting({day=0, night=0})
	vm:calc_lighting()
	vm:write_to_map(data)

	-----------------
	-- Place Doors --
	-----------------

	for current_door_index, current_door in pairs(doors) do

		local door_dir

		if current_door.ns then
			door_dir = minetest.dir_to_facedir({x = 0, y = 0, z = 1})
		else
			door_dir = minetest.dir_to_facedir({x = 1, y = 0, z = 0})
		end

		local door_pos = {x = current_door.x,
		                  y = current_door.y,
		                  z = current_door.z}

		minetest.set_node(door_pos, {name = "doors:door_wood_b_1",
		                             param2 = door_dir})
		door_pos.y = door_pos.y + 1
		minetest.set_node(door_pos, {name = "doors:door_wood_t_1",
		                             param2 = door_dir})

	end

	------------------
	-- Place Stairs --
	------------------

	for unused, s in pairs(stairs) do

		minetest.place_schematic({x = s.x, y = s.y + 1, z = s.z},
		                         schematic_stairs, s.dir * 90, {}, true)
		if chance(7,8) then
			minetest.set_node({x = s.x + halfrs,
			                   y = s.y + 2 * roomsize - 1,
			                   z = s.z + halfrs},
			                  {name = "default:torch"})
		end
	end
end)
