local player_lights = {}
local timer = 0

-- Load interval from settings (default to 0.15s if not set)
local UPDATE_INTERVAL = tonumber(minetest.settings:get("optiIllumanition.interval")) or 0.15

-- Helper: Check if node can be replaced by light
local function can_replace(pos)
	local node = minetest.get_node_or_nil(pos)
	return node and (node.name == "air" or minetest.get_item_group(node.name, "opti_illum_light") > 0)
end

local function remove_light(pos)
	if pos and can_replace(pos) then
		minetest.swap_node(pos, {name = "air"})
	end
end

-- Calculate total light level (wielded item + armor)
local function get_light_level(player)
	local light = 0
	
	-- Check wielded item
	local item = player:get_wielded_item():get_name()
	local def = minetest.registered_items[item]
	if def and def.light_source then
		light = def.light_source
	end

	-- Check armor (cached value)
	local name = player:get_player_name()
	if player_lights[name] and player_lights[name].armor_light then
		light = math.max(light, player_lights[name].armor_light)
	end

	return light
end

local function get_light_node(level)
	if level >= 14 then return "optiIllumanition:light_14"
	elseif level < 1 then return nil end
	return "optiIllumanition:light_" .. level
end

local function find_light_pos(pos)
	-- Check feet, then head, then nearby air
	if can_replace(pos) then return pos end
	pos.y = pos.y + 1
	if can_replace(pos) then return pos end
	return minetest.find_node_near(pos, 1, {"air", "group:opti_illum_light"})
end

local function update_illumination(player)
	local name = player:get_player_name()
	local data = player_lights[name]
	if not data then return end

	-- Get state
	local pos_raw = player:get_pos()
	local vel = player:get_velocity()
	
	-- Predict position (smooths lighting at speed)
	local grid_pos = vector.round(vector.add(pos_raw, vector.multiply(vel, 0.2)))
	local light_level = get_light_level(player)

	-- OPTIMIZATION: Stop if player hasn't moved nodes and light level is same
	if data.last_pos and vector.equals(grid_pos, data.last_pos) and data.last_light == light_level then
		return
	end

	-- Update cache
	data.last_pos = grid_pos
	data.last_light = light_level

	local wanted_node = get_light_node(light_level)
	local old_light_pos = data.current_light_pos

	-- Apply Light
	if wanted_node then
		local new_pos = find_light_pos(table.copy(grid_pos))
		
		if new_pos then
			-- If light moved or changed strength, update it
			if not old_light_pos or not vector.equals(new_pos, old_light_pos) or data.placed_node ~= wanted_node then
				minetest.swap_node(new_pos, {name = wanted_node})
				
				if old_light_pos and not vector.equals(old_light_pos, new_pos) then
					remove_light(old_light_pos)
				end
				
				data.current_light_pos = new_pos
				data.placed_node = wanted_node
			end
			return
		end
	end

	-- No valid light (or hidden), cleanup old
	if old_light_pos then
		remove_light(old_light_pos)
		data.current_light_pos = nil
		data.placed_node = nil
	end
end

-- Main Loop
minetest.register_globalstep(function(dtime)
	timer = timer + dtime
	if timer < UPDATE_INTERVAL then return end
	timer = 0 
	
	for _, player in pairs(minetest.get_connected_players()) do
		update_illumination(player)
	end
end)

-- Player Management
minetest.register_on_joinplayer(function(player)
	player_lights[player:get_player_name()] = { armor_light = 0 }
end)

minetest.register_on_leaveplayer(function(player)
	local name = player:get_player_name()
	if player_lights[name] and player_lights[name].current_light_pos then
		remove_light(player_lights[name].current_light_pos)
	end
	player_lights[name] = nil
end)

-- 3D Armor Support
if minetest.get_modpath("3d_armor") then
	armor:register_on_update(function(player)
		local name, inv = armor:get_valid_player(player)
		if name then
			local light = 0
			for i=1, inv:get_size("armor") do
				local stack = inv:get_stack("armor", i)
				if stack:get_count() > 0 then
					local def = minetest.registered_items[stack:get_name()]
					if def and def.light_source then
						light = math.max(light, def.light_source)
					end
				end
			end
			if player_lights[name] then
				player_lights[name].armor_light = light
				player_lights[name].last_light = -1 -- Force update
			end
		end
	end)
end

-- Register Light Nodes (Invisible, 1-14)
for n = 1, 14 do
	minetest.register_node("optiIllumanition:light_"..n, {
		drawtype = "airlike",
		paramtype = "light",
		light_source = n,
		sunlight_propagates = true,
		walkable = false,
		pointable = false,
		buildable_to = true,
		groups = {not_in_creative_inventory=1, opti_illum_light=1},
	})
end

-- Cleanup LBM (Removes stray lights on map load)
minetest.register_lbm({
	label = "Opti Illumination Cleanup",
	name = "optiIllumanition:cleanup",
	nodenames = {"group:opti_illum_light"},
	run_at_every_load = true,
	action = function(pos) minetest.set_node(pos, {name = "air"}) end,
})

-- Aliases
minetest.register_alias("optiIllumanition:light_faint", "optiIllumanition:light_4")
minetest.register_alias("optiIllumanition:light_dim", "optiIllumanition:light_8")
minetest.register_alias("optiIllumanition:light_mid", "optiIllumanition:light_12")
minetest.register_alias("optiIllumanition:light_full", "optiIllumanition:light_14")
