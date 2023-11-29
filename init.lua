local S = minetest.get_translator(minetest.get_current_modname())
local F = minetest.formspec_escape
local C = minetest.colorize

local currentGame = minetest.get_game_info().id

local recycler = {
    container_input = "input",
    container_output = "output",
    group_lookup = {},
    recipe_cache = {},
}

minetest.register_on_mods_loaded(function()
    for _, lst in ipairs({
        -- things that could be used to craft other things.
        minetest.registered_craftitems,
        minetest.registered_nodes,
        minetest.registered_items,
        minetest.registered_tools,

    }) do
        -- get first item in group for quick lookup
        -- wontfix: this is random because lua... bug becomes feature.
        for _, def in pairs(lst) do
            if def.groups then
                for groupname, _ in pairs(def.groups) do
                    if not recycler.group_lookup[groupname] then
                        recycler.group_lookup["group:" .. groupname] = {}
                    end
                    -- keep track of a few
                    if #recycler.group_lookup["group:" .. groupname] < 5 then
                        table.insert(recycler.group_lookup["group:" .. groupname], def.name)
                    end
                end
            end
        end
    end
end)

if currentGame == "minetest" then
    recycler.formspec = "size[8,8.5]" ..
        "list[current_player;main;0,4.25;8,1;]" ..
        "list[current_player;main;0,5.5;8,3;8]" ..
        "list[context;" .. recycler.container_input .. ";1.5,1.5;1,1;]" ..
        "list[context;" .. recycler.container_output .. ";3.5,0.5;3,3;]" ..
        "image[2.5,1.5;1,1;gui_furnace_arrow_bg.png^[transformR270]" ..
        "listring[current_player;main]" ..
        "listring[context;" .. recycler.container_input .. "]" ..
        "listring[context;" .. recycler.container_output .. "]" ..
        default.get_hotbar_bg(0, 4.25)
elseif currentGame == "mineclonia" then
    recycler.formspec = table.concat({
        "formspec_version[4]",
        "size[11.75,10.425]",

        "label[2.25,0.375;" .. F(C(mcl_formspec.label_color, S("Recycling"))) .. "]",

        mcl_formspec.get_itemslot_bg_v4(2, 2, 1, 1, 0.2),
        "list[context;" .. recycler.container_input .. ";2,2;1,1;]",

        "image[3.5,2;1.5,1;gui_crafting_arrow.png]",

        mcl_formspec.get_itemslot_bg_v4(5.5, 1, 3, 3),
        "list[context;" .. recycler.container_output .. ";5.5,1;3,3;]",

        "label[0.375,4.7;" .. F(C(mcl_formspec.label_color, S("Inventory"))) .. "]",

        mcl_formspec.get_itemslot_bg_v4(0.375, 5.1, 9, 3),
        "list[current_player;main;0.375,5.1;9,3;9]",

        mcl_formspec.get_itemslot_bg_v4(0.375, 9.05, 9, 1),
        "list[current_player;main;0.375,9.05;9,1;]",

        "listring[context;" .. recycler.container_input .. "]",
        "listring[context;" .. recycler.container_output .. "]",
        "listring[current_player;main]",

    })
end

-- test if an inventory list is empty
local inv_is_empty            = function(inv, listname)
    local size = inv:get_size(listname)
    for i = 1, size, 1 do
        local stack = inv:get_stack(listname, i)
        if "" ~= stack:get_name() and 0 ~= stack:get_count() then
            return false
        end
    end

    return true
end

-- clear target inventory list at position
local inv_clear               = function(pos, listname)
    local inv = minetest.get_meta(pos):get_inventory()
    local list = inv:get_list(listname)
    if not list then
        return
    end
    for index, _ in ipairs(list) do
        list[index] = ItemStack("")
    end
    inv:set_list(listname, list)
end

local get_item_from_group     = function(groupString)
    if recycler.group_lookup[groupString] then
        local randkey = math.random(#recycler.group_lookup[groupString])
        return recycler.group_lookup[groupString][randkey]
    end
    return ""
end

local get_first_normal_recipe = function(stack)
    local itemname = stack:get_name()
    local recipe = nil

    -- find and chache
    if not recycler.recipe_cache[itemname] then
        local recipes = minetest.get_all_craft_recipes(stack:get_name())
        local found = false
        -- print(dump(recipes))
        if recipes ~= nil then
            for _, tmp in pairs(recipes) do
                if tmp.method == "normal" and tmp.items then
                    recycler.recipe_cache[itemname] = {
                        recipe = {},
                        output = tmp.output,
                        inputStackCount = 0,
                    }

                    local rowWidth = tmp.width

                    -- full grid or formless already fit
                    if rowWidth == 3 or rowWidth == 0 then
                        recycler.recipe_cache[itemname].recipe = table.copy(tmp.items)
                    else
                        -- fake smaller width
                        for k, itm in ipairs(tmp.items) do
                            table.insert(recycler.recipe_cache[itemname].recipe, itm)

                            rowWidth = rowWidth - 1
                            -- used up row and not at end of item list.
                            if rowWidth == 0 then
                                -- pad the rest of the row with empty
                                for i = (3 - tmp.width), 1, -1 do
                                    table.insert(recycler.recipe_cache[itemname].recipe, "")
                                end
                                -- reset for next row
                                rowWidth = tmp.width
                            end
                        end
                    end

                    -- non empty stack count in recipe.
                    for _, val in pairs(recycler.recipe_cache[itemname].recipe) do
                        if val ~= "" then
                            recycler.recipe_cache[itemname].inputStackCount = recycler.recipe_cache[itemname]
                                .inputStackCount + 1
                        end
                    end

                    found = true
                    break
                end
            end
        end

        -- fallback, passtrough if no recipes found.
        if not found then
            local tmp3 = {}
            tmp3[5] = stack:to_string()
            recycler.recipe_cache[itemname] = {
                recipe = tmp3,
                output = stack:to_string(),
                inputStackCount = 1, -- should always be single stack
            }
        end
    end

    recipe = recycler.recipe_cache[itemname]

    local randomOutput = {}

    -- shuffle group items somewhat
    for k, itm in pairs(recipe.recipe) do
        if string.find(itm, "group:") then
            itm = get_item_from_group(itm)
        end
        randomOutput[k] = itm
    end

    return randomOutput, recipe.output, recipe.inputStackCount
end

local populate_output_grid    = function(pos, recipe, multiplier)
    local inv = minetest.get_meta(pos):get_inventory()
    for outindex, itx in pairs(recipe) do
        if itx ~= "" then
            local outstack = ItemStack(itx)
            -- quanity may get truncated if bigger than allowed stack size.
            outstack:set_count(outstack:get_count() * multiplier)
            inv:set_stack(recycler.container_output, outindex, outstack)
        end
    end
end

-- attempt recycling
-- @param pos vector
-- @returns boolean
local do_recycle              = function(pos)
    -- reread at each run in case you use the /set command.
    local leftoverFreebiesChance = math.min(1.0, math.max(0.0, tonumber(minetest.settings:get_bool("k_recyclebin.leftover_freebies_chance")))) or 0.8
    local minPartialRecycleRatio = math.min(1.0, math.max(0.0, tonumber(minetest.settings:get("k_recyclebin.partial_recycling_minimum_ratio")))) or 0.5

    local inv = minetest.get_meta(pos):get_inventory()
    local stack = inv:get_stack(recycler.container_input, 1)
    if
        inv_is_empty(inv, recycler.container_input)
    then
        -- might  be emptying output
        --print("do_recycle skip")
        return false
    end

    local recipe, recipeOutput, recipeItemCount = get_first_normal_recipe(stack)

    if recipeItemCount < 1 then
        return false
    end

    -- determine ratio of items we can recycle
    local idealInputStack         = ItemStack(recipeOutput)

    local idealInputCount         = idealInputStack:get_count()
    local idealOutputCount        = recipeItemCount

    -- number of full loops + remainders.
    local fullLoops               = math.floor(stack:get_count() / idealInputCount)
    local remainderItemsStackSize = math.fmod(stack:get_count(), idealInputCount)
    local remainderLoops          = math.ceil((remainderItemsStackSize / idealInputCount) * idealOutputCount) -- whole items where possible

    -- remainder has a chance of +1 extra
    -- more input items and smaller the output, higher the chance.
    -- add one more full loop and discard remainders.
    if leftoverFreebiesChance > 0.0 then
        local remainderFreebieChance = leftoverFreebiesChance * (remainderItemsStackSize * remainderLoops) /
            (idealInputCount * idealOutputCount)

        if math.random() < remainderFreebieChance then
            fullLoops = fullLoops + 1
            remainderLoops = 0
        end
    end


    -- refresh
    inv_clear(pos, recycler.container_output)

    -- set full recipes
    if fullLoops > 0 then
        populate_output_grid(pos, recipe, fullLoops)
    end

    if remainderLoops == 0 then
        return true
    end

    -- jitter somewhat to reduce item duplication
    -- should have at least half required stack, if not do a passthrough
    if minPartialRecycleRatio < (remainderItemsStackSize / idealInputCount) then
        -- some leftovers may be discarded.
        local leftoverStack = ItemStack(recipeOutput)
        leftoverStack:set_count(remainderItemsStackSize)
        if inv:room_for_item(recycler.container_output, leftoverStack) then
            inv:add_item(recycler.container_output, leftoverStack)
        end
    else
        -- randomize remainders
        local recipeKeys = {}
        for i, v in pairs(recipe) do
            if v ~= "" then
                table.insert(recipeKeys, i)
            end
        end
        table.shuffle(recipeKeys)

        -- shoud always be an item in there and remainder is less than recipeItemCount
        for _, outindex in pairs(recipeKeys) do
            if remainderLoops > 0 then
                local itx = recipe[outindex]
                local outstack = inv:get_stack(recycler.container_output, outindex)

                if outstack:item_fits(itx) then
                    -- leftovers may get lost.
                    outstack:add_item(itx)
                end

                inv:set_stack(recycler.container_output, outindex, outstack)

                remainderLoops = remainderLoops - 1
            end
        end
    end

    return true
end

--- define recycler node common.
local thedef                  = {
    description = S("Actual Recycle Bin"),
    tiles = {
        "k_recycler_top.png",
        "k_recycler_top.png",
        "k_recycler.png",
        "k_recycler.png",
        "k_recycler.png",
        "k_recycler.png"
    },
    drawtype = "nodebox",
    node_box = {
        type = "fixed",
        fixed = {
            { -0.4375, -0.5,   -0.4375, 0.4375, 0.25,   0.4375 }, -- can
            { -0.5,    0.25,   -0.5,    0.5,    0.4375, 0.5 },    -- lid
            { -0.125,  0.4375, -0.125,  0.125,  0.5,    0.125 },  -- nub
        }
    },
    _tt_help = S("Breaks down crafted things into original components. Mostly.."),
    paramtype = "light",
    selection_box = { type = "regular" },
    is_ground_content = false,
    groups = {
        handy = 1,
        material_metal = 1,
        deco_block = 1,
        dirtifier = 1,
        container = 1,
        cracky = 3, -- only breaks with pickaxe. oh well.
    },

    on_construct = function(pos)
        local meta = minetest.get_meta(pos)
        local inv = meta:get_inventory()
        inv:set_size(recycler.container_input, 1)
        inv:set_size(recycler.container_output, 3 * 3)
        meta:set_string("formspec", recycler.formspec)
        meta:set_int("hopper_wait", 0)
    end,


    on_receive_fields = function(pos, formname, fields, sender)
        -- might do something here later.
        --print("on_receive_fields: "..dump(formname) .. ", " ..dump(fields))
    end,

    after_dig_node = function(pos, oldnode, oldmetadata, digger) -- Modified from the one of furnaces
        if not oldmetadata.inventory then return end
        for _, listname in ipairs({ recycler.container_input, recycler.container_output }) do
            if oldmetadata.inventory[listname] then
                for _, stack in ipairs(oldmetadata.inventory[listname]) do
                    if stack then
                        stack = ItemStack(stack) -- Ensure it is an ItemStack
                        if not stack:is_empty() then
                            local drop_offset = vector.new(math.random() - 0.5, 0, math.random() - 0.5)
                            minetest.add_item(vector.add(pos, drop_offset), stack)
                        end
                    end
                end
            end
        end
    end,

    on_destruct = function(pos)
        -- should do something here I feel
        local meta = minetest.get_meta(pos)
        meta:set_string("formspec", "")
        meta:set_int("hopper_wait", 0)
    end,

    allow_metadata_inventory_put = function(pos, listname, index, stack, player)
        local meta = minetest.get_meta(pos)
        local inv = meta:get_inventory()

        if listname == recycler.container_input
            and inv_is_empty(inv, listname)
            and not inv_is_empty(inv, recycler.container_output)
        then
            --print("can't put things in input if output is partially cleared." .. dump(inv_empty(inv, listname)) .. " " ..dump(inv_empty(inv, recycler.container_output)))
            return 0
        end

        if listname == recycler.container_output then
            --print("can't put things in output")
            return 0
        end

        return stack:get_count()
    end,

    on_metadata_inventory_put = function(pos, listname, index, stack, player)
        --print("on_metadata_inventory_put " .. dump(stack:get_name()) .. " " .. stack:get_count())
        if listname == recycler.container_input
            and not stack:is_empty()
        then
            if do_recycle(pos) then
                minetest.log("info", string.format("Recylebin: %s recycled %", player:get_name(), stack:to_string()))
            else
                -- something else
            end
        end
    end,

    allow_metadata_inventory_take = function(pos, listname, index, stack, player)
        -- tbd.
        return stack:get_count()
    end,

    on_metadata_inventory_take = function(pos, listname, index, stack, player)
        -- clear output if we remove input.
        if listname == recycler.container_input then
            inv_clear(pos, recycler.container_output)
        end

        -- clear input when we take retrieve items from output.
        if listname == recycler.container_output then
            inv_clear(pos, recycler.container_input)
        end
    end,

    allow_metadata_inventory_move = function(pos, from_list, from_index, to_list, to_index, count, player)
        -- this handler might not be needed
        if
        -- can't move things to output
            to_list == recycler.container_output
            -- or from output to input.
            -- need to clear output before recycling new item.
            or (from_list == recycler.container_output and to_list == recycler.container_input)
        then
            return 0
        end

        return count
    end,
}

-- minetest
if currentGame == "minetest" then
    thedef.sounds = default.node_sound_stone_defaults()
    thedef._mcl_blast_resistance = 99 -- creepers can't get into trash cans.
    thedef._mcl_hardness = 3
    minetest.register_craft({
        output = "k_recyclebin:recyclebin",
        recipe = {
            { "default:steel_ingot", "default:diamondblock", "default:steel_ingot" },
            { "default:steel_ingot", "default:furnace",      "default:steel_ingot" },
            { "default:steel_ingot", "default:chest",        "default:steel_ingot" },
        }
    })
    -- mineclonia
elseif currentGame == "mineclonia" then
    thedef.sounds = mcl_sounds.node_sound_metal_defaults()

    thedef._on_hopper_in = function(hopper_pos, to_pos)
        -- try to pull ideal amount items for a full recycle
        local meta = minetest.get_meta(to_pos)
        local inv = meta:get_inventory()

        local hopperInv = minetest.get_meta(hopper_pos):get_inventory()

        -- skip is in process of emptying or still processing
        if
            not inv_is_empty(inv, recycler.container_input)
            or not inv_is_empty(inv, recycler.container_output)
        then
            --print("_on_hopper_in skip")
            return false
        end

        local slotId = mcl_util.get_first_occupied_inventory_slot(hopperInv, "main")

        if not slotId then
            return false
        end

        local inputStack = hopperInv:get_stack("main", slotId)
        if not inputStack then
            return false
        end

        local _, recipeOutput, _ = get_first_normal_recipe(inputStack)

        local idealRecipeStack   = ItemStack(recipeOutput)
        local itemToMoveCount    = math.min(inputStack:get_count(), idealRecipeStack:get_count())

        -- bit messy wait logic to try and get a minimum usable stack.
        local hopperWaited       = false

        if (meta:get_int("hopper_wait") > 0) then
            meta:set_int("hopper_wait", meta:get_int("hopper_wait") - 1)
            if meta:get_int("hopper_wait") == 0 then
                hopperWaited = true
            else
                return false
            end
        end

        if not hopperWaited and itemToMoveCount < idealRecipeStack:get_count() then
            -- wait a bit more than min amount of extra items to push.
            -- wonky but close enough
            meta:set_int("hopper_wait", 2 + idealRecipeStack:get_count() - itemToMoveCount)

            return false
        else
            meta:set_int("hopper_wait", 0)
        end

        -- move full stack into recycler if possible
        local sucked = false

        while itemToMoveCount > 0 do
            itemToMoveCount = itemToMoveCount - 1
            -- reuse built in util because there may be oddities it takes of.
            sucked = mcl_util.move_item_container(hopper_pos, to_pos, nil, nil, recycler.container_input)
        end

        -- hopper doesn't trigger on_put
        do_recycle(to_pos)

        return sucked
    end

    thedef._on_hopper_out = function(from_pos, hopper_pos)
        -- Suck items from the container into the hopper
        local sucked = mcl_util.move_item_container(from_pos, hopper_pos, recycler.container_output)

        local inv = minetest.get_meta(from_pos):get_inventory()
        if sucked then
            -- clear input when we take retrieve items from output.
            -- hopper doesn't trigger on_take
            inv_clear(from_pos, recycler.container_input)
        end
        return sucked
    end


    minetest.register_craft({
        output = "k_recyclebin:recyclebin",
        recipe = {
            { "mcl_core:iron_ingot",  "mesecons_torch:redstoneblock",      "mcl_core:iron_ingot" },
            { "mcl_furnaces:furnace", "mcl_crafting_table:crafting_table", "mcl_composters:composter" },
            { "mcl_core:iron_ingot",  "mcl_chests:chest",                  "mcl_core:iron_ingot" },
        }
    })

    minetest.register_craft({
        output = "k_recyclebin:recyclebin",
        recipe = {
            { "mcl_core:iron_ingot",      "mesecons_torch:redstoneblock",      "mcl_core:iron_ingot" },
            { "mcl_composters:composter", "mcl_crafting_table:crafting_table", "mcl_furnaces:furnace" },
            { "mcl_core:iron_ingot",      "mcl_chests:chest",                  "mcl_core:iron_ingot" },
        }
    })
end

minetest.register_node("k_recyclebin:recyclebin", thedef)
-- old version alias
minetest.register_alias("k_actual_recyclebin:recyclebin", "k_recyclebin:recyclebin")