local load_time_start = os.clock()

local function get_pointed_info(pointed_thing)
	if not pointed_thing then
		return
	end
	local pu = minetest.get_pointed_thing_position(pointed_thing)
	local pa = minetest.get_pointed_thing_position(pointed_thing, true)
	if not (pu and pa) then
		return
	end
	if pu.y ~= pa.y then
		return
	end
	local nd_u = minetest.get_node(pu)
	if nd_u.name ~= "default:chest" then
		return
	end
	return pu, pa, nd_u.param2
end

local big_chest_formspec = 
	"size[13,9]"..
	"list[current_name;main;0,0;13,5;]"..
	"list[current_player;main;2.5,5.2;8,4;]"

local param_tab = {
	["-1 0"] = 0,
	 ["1 0"] = 2,
	["0 -1"] = 3,
	 ["0 1"] = 1,
}

local pars = {[0]=2, 3, 0, 1}

local function connect_chests(pu, pa, old_param2)
	local stuff = minetest.get_meta(pu):get_inventory():get_list("main")

	local par = param_tab[pu.x-pa.x.." "..pu.z-pa.z]
	if param_tab[pa.x-pu.x.." "..pa.z-pu.z] == old_param2 then
		pu, pa = pa, pu
		par = pars[par]
	end
	minetest.add_node(pu, {name="connected_chests:chest_left", param2=par})
	minetest.add_node(pa, {name="connected_chests:chest_right", param2=par})

	local meta = minetest.get_meta(pu)
	meta:set_string("formspec", big_chest_formspec)
	meta:set_string("infotext", "Big Chest")
	local inv = meta:get_inventory()
	inv:set_size("main", 65)
	inv:set_list("main", stuff)
end

local place_chest = minetest.registered_nodes["default:chest"].on_place
minetest.override_item("default:chest", {
	on_place = function(itemstack, placer, pointed_thing)
		if not placer then
			return
		end
		local pu, pa, nd_u = get_pointed_info(pointed_thing)
		if not pu then
			return place_chest(itemstack, placer, pointed_thing)
		end
		local protected = minetest.is_protected(pa, placer:get_player_name())
		if protected then
			return
		end
		connect_chests(pu, pa, nd_u)
		itemstack:take_item()
		return itemstack
	end
})

local function remove_next(pos, oldnode)
	local p1 = oldnode.param2
	for p,param in pairs(param_tab) do
		if param == p1 then
			p1 = p
			break
		end
	end
	local x, z = unpack(string.split(p1, " "))
	pos.x = pos.x-x
	pos.z = pos.z-z
	minetest.remove_node(pos)
end

minetest.register_node("connected_chests:chest_left", {
	tiles = {"connected_chests_top.png", "connected_chests_top.png", "default_obsidian_glass.png",
		"default_chest_side.png", "connected_chests_side.png^[transformFX", "connected_chests_side.png^connected_chests_front.png"},
	paramtype2 = "facedir",
	drop = "default:chest 2",
	groups = {choppy=2,oddly_breakable_by_hand=2},
	is_ground_content = false,
	sounds = default.node_sound_wood_defaults(),
	selection_box = {
		type = "fixed",
		fixed = {
			{-0.5, -0.5, -0.5, 1.5, 0.5, 0.5},
		},
	},
	can_dig = function(pos)
		local meta = minetest.get_meta(pos);
		local inv = meta:get_inventory()
		return inv:is_empty("main")
	end,
	after_dig_node = remove_next,
	on_metadata_inventory_move = function(pos, _, _, _, _, _, player)
		minetest.log("action", player:get_player_name()..
				" moves stuff in big chest at "..minetest.pos_to_string(pos))
	end,
    on_metadata_inventory_put = function(pos, _, _, _, player)
		minetest.log("action", player:get_player_name()..
				" moves stuff to big chest at "..minetest.pos_to_string(pos))
	end,
    on_metadata_inventory_take = function(pos, _, _, _, player)
		minetest.log("action", player:get_player_name()..
				" takes stuff from big chest at "..minetest.pos_to_string(pos))
	end,
})


local function has_locked_chest_privilege(meta, player)
	if player:get_player_name() ~= meta:get_string("owner") then
		return false
	end
	return true
end

minetest.register_node("connected_chests:chest_locked_left", {
	tiles = {"connected_chests_top.png", "connected_chests_top.png", "default_obsidian_glass.png",
		"default_chest_side.png", "connected_chests_side.png^[transformFX", "connected_chests_side.png^connected_chests_lock.png"},
	paramtype2 = "facedir",
	drop = "default:chest_locked 2",
	groups = {choppy=2,oddly_breakable_by_hand=2},
	is_ground_content = false,
	sounds = default.node_sound_wood_defaults(),
	selection_box = {
		type = "fixed",
		fixed = {
			{-0.5, -0.5, -0.5, 1.5, 0.5, 0.5},
		},
	},
	after_place_node = function(pos, placer)
		local meta = minetest.get_meta(pos)
		meta:set_string("owner", placer:get_player_name() or "")
		meta:set_string("infotext", "Locked Chest (owned by "..
				meta:get_string("owner")..")")
	end,
	--[[on_construct = function(pos)
		local meta = minetest.get_meta(pos)
		meta:set_string("infotext", "Locked Chest")
		meta:set_string("owner", "")
		local inv = meta:get_inventory()
		inv:set_size("main", 8*4)
	end,]]
	can_dig = function(pos, player)
		local meta = minetest.get_meta(pos);
		local inv = meta:get_inventory()
		return inv:is_empty("main") and has_locked_chest_privilege(meta, player)
	end,
	after_dig_node = remove_next,
	allow_metadata_inventory_move = function(pos, from_list, from_index, to_list, to_index, count, player)
		local meta = minetest.get_meta(pos)
		if not has_locked_chest_privilege(meta, player) then
			minetest.log("action", player:get_player_name()..
					" tried to access a locked chest belonging to "..
					meta:get_string("owner").." at "..
					minetest.pos_to_string(pos))
			return 0
		end
		return count
	end,
    allow_metadata_inventory_put = function(pos, listname, index, stack, player)
		local meta = minetest.get_meta(pos)
		if not has_locked_chest_privilege(meta, player) then
			minetest.log("action", player:get_player_name()..
					" tried to access a locked chest belonging to "..
					meta:get_string("owner").." at "..
					minetest.pos_to_string(pos))
			return 0
		end
		return stack:get_count()
	end,
    allow_metadata_inventory_take = function(pos, listname, index, stack, player)
		local meta = minetest.get_meta(pos)
		if not has_locked_chest_privilege(meta, player) then
			minetest.log("action", player:get_player_name()..
					" tried to access a locked chest belonging to "..
					meta:get_string("owner").." at "..
					minetest.pos_to_string(pos))
			return 0
		end
		return stack:get_count()
	end,
	on_metadata_inventory_move = function(pos, _, _, _, _, _, player)
		minetest.log("action", player:get_player_name()..
				" moves stuff in big locked chest at "..minetest.pos_to_string(pos))
	end,
    on_metadata_inventory_put = function(pos, _, _, _, player)
		minetest.log("action", player:get_player_name()..
				" moves stuff to big locked chest at "..minetest.pos_to_string(pos))
	end,
    on_metadata_inventory_take = function(pos, _, _, _, player)
		minetest.log("action", player:get_player_name()..
				" takes stuff from big locked chest at "..minetest.pos_to_string(pos))
	end,
	on_rightclick = function(pos, node, clicker)
		local meta = minetest.get_meta(pos)
		if has_locked_chest_privilege(meta, clicker) then
			minetest.show_formspec(
				clicker:get_player_name(),
				"default:chest_locked",
				default.get_locked_chest_formspec(pos)
			)
		end
	end,
})

minetest.register_node("connected_chests:chest_right", {
	tiles = {"connected_chests_top.png^[transformFX", "connected_chests_top.png^[transformFX", "default_chest_side.png",
		"default_obsidian_glass.png", "connected_chests_side.png", "connected_chests_side.png^connected_chests_front.png^[transformFX"},
	paramtype2 = "facedir",
	drop = "",
	is_ground_content = false,
	pointable = false,
	can_dig = function()
		return false
	end,
})

minetest.register_node("connected_chests:chest_locked_right", {
	tiles = {"connected_chests_top.png^[transformFX", "connected_chests_top.png^[transformFX", "default_chest_side.png",
		"default_obsidian_glass.png", "connected_chests_side.png", "connected_chests_side.png^connected_chests_lock.png^[transformFX"},
	paramtype2 = "facedir",
	drop = "",
	is_ground_content = false,
	pointable = false,
	can_dig = function()
		return false
	end,
})

print(string.format("[connected_chest] loaded after ca. %.2fs", os.clock() - load_time_start))
