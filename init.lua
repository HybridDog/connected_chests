local load_time_start = minetest.get_us_time()


-- param_tab maps the x and z offset to a param2 value
local param_tab = {
	["-1 0"] = 0,
	 ["1 0"] = 2,
	["0 -1"] = 3,
	 ["0 1"] = 1,
}

-- param_tab2 maps the other way round
local param_tab2 = {}
for n,i in pairs(param_tab) do
	param_tab2[i] = n:split" "
end

local function return_remove_next(allowed_name)
	local function remove_next(pos, oldnode)
		-- if the left node had an unexpected rotation, the right one can't be
		-- found, in this case simply do nothing
		if oldnode.param2 > 3 then
			return
		end

		-- remove the right one if there is one
		-- (the left one is already removed)
		local x, z = unpack(param_tab2[oldnode.param2])
		pos.x = pos.x-x
		pos.z = pos.z-z
		if minetest.get_node(pos).name == allowed_name then
			minetest.remove_node(pos)
		end
	end
	return remove_next
end


-- used when constructing the left node
local function return_add_next(right_name)
	local function add_next(pos, node)
		node = node or minetest.get_node(pos)
		local par = node.param2

		-- if the left node is set with an unexpected rotation, put the chest
		-- with default rotation
		if par > 3 then
			node.param2 = 0
			minetest.set_node(pos, node)
			return
		end

		-- put the right chest if possible
		local x, z = unpack(param_tab2[par])
		pos.x = pos.x-x
		pos.z = pos.z-z
		if minetest.get_node(pos).name == "air" then
			minetest.set_node(pos, {name=right_name, param2=par})
		end
	end
	return add_next
end


-- gives information about the positions and param to place the nodes
local function get_pointed_info(pt, name)
	if not pt then
		return
	end
	local pu = minetest.get_pointed_thing_position(pt)
	local pa = minetest.get_pointed_thing_position(pt, true)
	if not pu
	or not pa
	or pu.y ~= pa.y then
		return
	end
	local nd_u = minetest.get_node(pu)
	if nd_u.name ~= name then
		return
	end
	return pu, pa, nd_u.param2
end




local pars = {[0]=2, 3, 0, 1}

local chestdata = {}


-- executed when connecting the chests
local function connect_chests(pu, pa, old_param2, name)
	local metatable = minetest.get_meta(pu):to_table()

	local par = param_tab[pu.x-pa.x.." "..pu.z-pa.z]
	local par_inverted = pars[par]
	if old_param2 == par_inverted then
		pu, pa = pa, pu
		par = par_inverted
	end

	chestdata[name].on_connect(pu, pa, par, metatable)
end


local tube_to_left, tube_to_left_locked, tube_update, tube_groups
if minetest.global_exists"pipeworks" then
	tube_to_left_locked = {
		insert_object = function(pos, node, stack)
			local x, z = unpack(param_tab2[node.param2])
			return minetest.get_meta{x=pos.x+x, y=pos.y, z=pos.z+z
				}:get_inventory():add_item("main", stack)
		end,
		can_insert = function(pos, node, stack)
			local x, z = unpack(param_tab2[node.param2])
			return minetest.get_meta{x=pos.x+x, y=pos.y, z=pos.z+z
				}:get_inventory():room_for_item("main", stack)
		end,
		connect_sides = {right = 1, back = 1, front = 1, bottom = 1, top = 1}
	}

	tube_to_left = table.copy(tube_to_left_locked)
	tube_to_left.input_inventory = "main"

	tube_update = pipeworks.scan_for_tube_objects

	tube_groups = {tubedevice=1, tubedevice_receiver=1}
else
	function tube_update() end
end


connected_chests = {chestdata = chestdata}
--[[
connected_chests.register_chest(<original_node>, {
	get_formspec = function(metatable, pos)
		return <formspec_of_big>
	end,
	lock = true, -- indicates whether a lock should be added to the texture
		-- and has an impact on the tube function
	front = <keyhole_texture>, -- if present, this texture is added to the chest
		-- front
	on_rightclick = <func>, -- sets an on_rightclick (some chests need this)
})
]]

function connected_chests.register_chest(fromname, data)
	chestdata[fromname] = data

	--~ local mod, name = fromname:split":"
	local name_left = fromname .. "_connected_left"
	local name_right = fromname .. "_connected_right"
	data.left = name_left
	data.right = name_right

	-- executed when connecting the chest
	data.on_connect = function(pu, pa, par, metatable)
		minetest.add_node(pu, {name=name_left, param2=par})
		minetest.add_node(pa, {name=name_right, param2=par})

		metatable.fields.formspec = data.get_formspec(metatable, pu)
		metatable.fields.infotext = "Big " .. metatable.fields.infotext
		local meta = minetest.get_meta(pu)
		meta:from_table(metatable)
		local inv = meta:get_inventory()
		inv:set_size("main", 65)

	end

	-- override the original node to support connecting
	local place_chest = minetest.registered_nodes[fromname].on_place
	local creative_mode = minetest.settings:get_bool"creative_mode"
	minetest.override_item(fromname, {
		on_place = function(itemstack, placer, pointed_thing)
			if not placer
			or not placer:get_player_control().sneak then
				return place_chest(itemstack, placer, pointed_thing)
			end
			local pu, pa, par2 = get_pointed_info(pointed_thing, fromname)
			if not pu then
				return place_chest(itemstack, placer, pointed_thing)
			end
			if minetest.is_protected(pa, placer:get_player_name()) then
				return
			end
			connect_chests(pu, pa, par2, fromname)
			if not creative_mode then
				itemstack:take_item()
				return itemstack
			end
		end
	})


	-- Adds the big chest nodes

	-- the left one contains inventory
	local chest = {}
	local origdef = minetest.registered_nodes[fromname]
	for i in pairs(origdef) do
		chest[i] = rawget(origdef, i)
	end

	local top = chest.tiles[1]
	local side = chest.tiles[4]
	local top_texture = top .. "^([combine:16x16:5,0=" .. top ..
		"^connected_chests_frame.png^[makealpha:255,126,126)"
	local side_texture = side .. "^([combine:16x16:5,0=" .. side ..
		"^connected_chests_frame.png^[makealpha:255,126,126)"


	chest.description = "Big " .. chest.description
	chest.groups = table.copy(chest.groups)
	chest.groups.not_in_creative_inventory = 1
	chest.legacy_facedir_simple = nil
	chest.after_place_node = nil
	chest.on_receive_fields = nil
	if data.on_rightclick then
		chest.on_rightclick = data.on_rightclick
	end

	-- disallow rotating a connected chest using a screwdriver
	function chest.on_rotate()
		return false
	end

	-- copy pipeworks tube data (if requisite)
	if chest.tube then
		chest.tube = table.copy(chest.tube)
		chest.tube.connect_sides = {left = 1, -- no connection to the right.
			back = 1, front = 1, bottom = 1, top = 1}
	end

	if not data.front then
		data.front = "connected_chests_front.png"
		if data.lock then
			data.front = data.front .. "^connected_chests_lock.png"
		end
	end
	chest.tiles = {top_texture, top_texture, "default_obsidian_glass.png",
		side, side_texture.."^[transformFX", side_texture.."^" .. data.front}
	chest.drop = (chest.drop or fromname) .. " 2"
	chest.selection_box = {
		type = "fixed",
		fixed = {
			{-0.5, -0.5, -0.5, 1.5, 0.5, 0.5},
		},
	}
	chest.on_construct = return_add_next(name_right)
	chest.after_destruct = return_remove_next(name_right)

	--~ minetest.register_node("connected_chests:chest_left", chest)
	minetest.register_node(":" .. name_left, chest)


	-- the right one is the deco one
	local tiles = {top_texture.."^[transformFX", top_texture.."^[transformFX",
		side, "default_obsidian_glass.png", side_texture, side_texture
		.. "^" .. data.front .. "^[transformFX"}
	minetest.register_node(":" .. name_right, {
		tiles = tiles,
		paramtype2 = "facedir",
		drop = "",
		pointable = false,
		diggable = false,
		on_construct = function(pos)
			local node = minetest.get_node(pos)

			-- if the right node has an unexpected rotation, try to set it with
			-- a valid one
			if node.param2 > 3 then
				node.param2 = node.param2 % 4
				minetest.set_node(pos, node)
				return
			end

			-- remove it if the left node can't be found
			local x, z = unpack(param_tab2[node.param2])
			local node_left = minetest.get_node{x=pos.x+x, y=pos.y, z=pos.z+z}
			if node_left.name ~= name_left
			or node_left.param2 ~= node.param2 then
				minetest.remove_node(pos)
				return
			end

			-- connect pipework tubes if there are any
			tube_update(pos)
		end,
		after_destruct = function(pos, oldnode)
			-- simply remove the right node if it has an unexpected rotation
			if oldnode.param2 > 3 then
				return
			end

			-- add it back if the left node is still there
			local x, z = unpack(param_tab2[oldnode.param2])
			local node_left = minetest.get_node{x=pos.x+x, y=pos.y, z=pos.z+z}
			if node_left.name == name_left
			and node_left.param2 == oldnode.param2
			and minetest.get_node(pos).name == "air" then
				minetest.set_node(pos, oldnode)
				return
			end

			-- disconnect pipework tubes if there are any
			tube_update(pos)
		end,
		tube = data.lock and tube_to_left_locked or tube_to_left,
		groups = tube_groups,
	})
end


local big_formspec = "size[13,9]"..
	"list[current_name;main;0,0;13,5;]"..
	"list[current_player;main;2.5,5.2;8,4;]"..
	"listring[current_name;main]"..
	"listring[current_player;main]"


connected_chests.register_chest("default:chest", {
	get_formspec = function()
		return big_formspec
	end,
	on_rightclick = function(pos, _, player)
		minetest.sound_play("default_chest_open", {gain = 0.3,
				pos = pos, max_hear_distance = 10})

		minetest.show_formspec(
			player:get_player_name(),
			"default:chest_locked_connected_left",
			"size[13,9]"..
			"list[nodemeta:".. pos.x .. "," .. pos.y .. "," ..pos.z .. ";main;0,0;13,5;]"..
			"list[current_player;main;2.5,5.2;8,4;]"
		)
	end

})

connected_chests.register_chest("default:chest_locked", {
	get_formspec = function()
		return big_formspec
	end,
	lock = true,
	on_rightclick = function(pos, _, player)
		if not default.can_interact_with_node(player, pos) then
			minetest.sound_play("default_chest_locked", {pos = pos})
			return
		end

		minetest.sound_play("default_chest_open", {gain = 0.3,
				pos = pos, max_hear_distance = 10})

		minetest.show_formspec(
			player:get_player_name(),
			"default:chest_locked_connected_left",
			"size[13,9]"..
			"list[nodemeta:".. pos.x .. "," .. pos.y .. "," ..pos.z .. ";main;0,0;13,5;]"..
			"list[current_player;main;2.5,5.2;8,4;]"
		)
	end
})



-- abms to fix half chests
for _,i in pairs(chestdata) do
	minetest.register_abm{
		nodenames = {i.right},
		interval = 10,
		chance = 1,
		action = function(pos, node)
			if node.param2 > 3 then
				node.param2 = node.param2%4
				minetest.set_node(pos, node)
				return
			end
			local x, z = unpack(param_tab2[node.param2])
			local left_node = minetest.get_node{x=pos.x+x, y=pos.y, z=pos.z+z}
			if left_node.name ~= i.left
			or left_node.param2 ~= node.param2 then
				minetest.remove_node(pos)
			end
		end,
	}
	minetest.register_abm{
		nodenames = {i.left},
		interval = 3,
		chance = 1,
		action = return_add_next(i.right),
	}
end



-- legacy
minetest.register_alias("connected_chests:chest_left",
	"default:chest_connected_left")
minetest.register_alias("connected_chests:chest_right",
	"default:chest_connected_right")
minetest.register_alias("connected_chests:chest_left_locked", "default:chest_locked_connected_left")
minetest.register_alias("connected_chests:chest_right_locked", "default:chest_locked_connected_right")

--~ local function log_access(pos, player, text)
	--~ minetest.log("action", player:get_player_name()..
		--~ " moves stuff "..text.." at "..minetest.pos_to_string(pos))
--~ end


local time = (minetest.get_us_time() - load_time_start) / 1000000
local msg = "[connected_chests] loaded after ca. " .. time .. " seconds."
if time > 0.01 then
	print(msg)
else
	minetest.log("info", msg)
end
