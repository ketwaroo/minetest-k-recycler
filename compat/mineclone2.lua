local get_first_occupied_inventory_slot = function(src_inventory, src_list) end
local move_item_container = function(source_pos, destination_pos, source_list, source_stack_id, destination_list) end

if nil == mcl_util.get_first_occupied_inventory_slot then
    get_first_occupied_inventory_slot = function(src_inventory, src_list)
        local size = src_inventory:get_size(src_list)
        local stack
        for i = 1, size do
            stack = src_inventory:get_stack(src_list, i)
            if not stack:is_empty() then
                return i
            end
        end
        return nil
    end
else
    get_first_occupied_inventory_slot = mcl_util.get_first_occupied_inventory_slot
end

if nil == mcl_util.move_item_container then
    move_item_container = function(source_pos, destination_pos, source_list, source_stack_id, destination_list)
        -- skipping a bunch of checks and sanitisation that mineclonia offers.
        -- may expolode and destroy your world.
        -- use the the better minetest minecraft clone to avoid that.
        if not source_pos or not destination_pos then return false end

        local smeta = minetest.get_meta(source_pos)
        local dmeta = minetest.get_meta(destination_pos)

        local source_inventory = smeta:get_inventory()
        local destination_inventory = dmeta:get_inventory()

        if not source_stack_id then
            source_stack_id = -1
        end

        -- those should be hopper lists.
        if nil == destination_list then
            destination_list = "main"
        end

        if nil == source_list then
            source_list = "main"
        end
        -- print("movecompat1" .. dump(source_list) .. dump(source_stack_id) .. dump(destination_list))
        if source_stack_id == -1 then
            source_stack_id = get_first_occupied_inventory_slot(source_inventory, source_list)
            -- print("movecompat2" .. dump(source_stack_id))
            if source_stack_id == nil then
                return false
            end
        end

        -- print("movecompat3" .. dump(source_stack_id))

        return mcl_util.move_item(source_inventory, source_list, source_stack_id, destination_inventory, destination_list)
    end
else
    move_item_container = mcl_util.move_item_container
end

return get_first_occupied_inventory_slot, move_item_container
