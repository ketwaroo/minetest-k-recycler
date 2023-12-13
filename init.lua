-- K Recycle Bin
-- 2023 (c) Ketwaroo

local S = minetest.get_translator(minetest.get_current_modname())
local F = minetest.formspec_escape

local recycler = {
    container_input = "input",
    container_output = "output",
    group_lookup = {},
    recipe_cache = {},
    hopper_mode_timeout = 3, -- wait in seconds. should be bigger than rate hopper is pushing items by default. might be a race condition waiting to happen.
    default_trash = nil,
}

minetest.register_on_mods_loaded(function()
    local groupSampleSize = math.max(1, (tonumber(minetest.settings:get("k_recyclebin.group_item_mapping_sample_size") or 1)))
    for _, lst in ipairs({
        -- things that could be used to craft other things.
        minetest.registered_craftitems,
        minetest.registered_nodes,
        minetest.registered_items,
        minetest.registered_tools,

    }) do
        -- get first N item in group for quick lookup
        -- wontfix: this is random because lua... bug becomes feature.
        for _, def in pairs(lst) do
            if def.groups then
                for groupname, _ in pairs(def.groups) do
                    -- prepend group: for quicker lookup
                    local gn = "group:" .. groupname
                    if not recycler.group_lookup[gn] then
                        recycler.group_lookup[gn] = {}
                    end
                    -- keep track of a few
                    if #recycler.group_lookup[gn] < groupSampleSize then
                        table.insert(recycler.group_lookup[gn], def.name)
                    end
                end
            end
        end
    end
    -- print(dump(recycler.group_lookup))

    -- @todo for destroy mode, need more dynamic way of determining default trash.
    if minetest.get_modpath("default") then
        recycler.default_trash = "default:coal_lump"
    elseif minetest.get_modpath("core") then
        recycler.default_trash = "mcl_core:coal_lump"
    end
end)

local get_recycler_formspec   = function(pos)
    local formspecString

    local meta = minetest.get_meta(pos)

    local hopperMode = "false"
    local destroyMode = "false"

    if 1 == meta:get_int("hopper_mode") then
        hopperMode = "true"
    end

    if 1 == meta:get_int("destroy_mode") then
        destroyMode = "true"
    end

    -- default inventory is 8 wide
    -- mineclonia is 9
    local invWidth = 8
    if minetest.get_modpath("mcl_formspec") then
        invWidth = 9
    end

    local inOutPadding = (invWidth - 5) / 2

    -- minecraft inv bar is usually at bottom
    local invBarY = 4
    local invGridY = 5.5
    local arrowImg = "gui_furnace_arrow_bg.png^[transformR270]"
    if minetest.get_modpath("mcl_formspec") then
        invGridY = 4
        invBarY = 7.5
        arrowImg = "gui_crafting_arrow.png"
    end

    formspecString = table.concat({
        "size[" .. (invWidth + 1) .. ",8.5]",
        "label[0.25,0;" .. F(S("Recycling")) .. "]",
        "list[context;" .. recycler.container_input .. ";" .. inOutPadding .. ",1.5;1,1;]",
        "image[" .. (inOutPadding + 1) .. ",1.5;1,1;" .. arrowImg .. "]",
        "list[context;" .. recycler.container_output .. ";" .. (inOutPadding + 2) .. ",0.5;3,3;]",
        "label[0.25,3.5;" .. F(S("Inventory")) .. "]",
        "list[current_player;main;0.5," .. invBarY .. ";" .. invWidth .. ",1;]",
        "list[current_player;main;0.5," .. invGridY .. ";" .. invWidth .. ",3;" .. invWidth .. "]",
        -- destroyMode
        "checkbox[" .. (inOutPadding + 5.25) .. ",1.0;destroy_mode;" .. F(S("Destroy Mode")) .. ";" .. destroyMode .. "]",
        "tooltip[destroy_mode;" .. F(S(
            "Destroy Mode will attempt to break down unrecyclable items.\n" ..
            "May destroy things.. as the name suggests."
        )) .. "]"
    })

    -- why backgounds tho
    if minetest.get_modpath("mcl_formspec") then
        formspecString = formspecString .. table.concat({
            --input
            mcl_formspec.get_itemslot_bg(inOutPadding, 1.5, 1, 1),
            -- output
            mcl_formspec.get_itemslot_bg((inOutPadding + 2), 0.5, 3, 3),
            -- inventory
            mcl_formspec.get_itemslot_bg(0.5, invGridY, invWidth, 3),
            mcl_formspec.get_itemslot_bg(0.5, invBarY, invWidth, 1),
        })
    end

    -- only for games with the hopper mod
    -- probably incompatible with mineclonia hopper API
    if minetest.get_modpath("hopper") then
        formspecString = formspecString .. "checkbox[" .. (inOutPadding + 5.25) .. ",0.5;hopper_mode;" .. F(S("Hopper Mode")) .. ";" .. hopperMode .. "]" ..
            "tooltip[hopper_mode;" .. F(S(
                "Hopper Mode forces recycle bin to wait until a\n" ..
                "certain minimum number of items are fed into input\n" ..
                "before processing.\n" ..
                "For best results, use when connected with hoppers."))
            .. "]"
    end

    -- items should move from main to input, input to main, output to main on shift click
    formspecString = formspecString ..
        "listring[current_player;main]" ..
        "listring[context;" .. recycler.container_input .. "]" ..
        "listring[current_player;main]" ..
        "listring[context;" .. recycler.container_output .. "]" ..
        "listring[current_player;main]"

    return formspecString
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

-- eject a stack of items at a position
local pop_excess              = function(pos, stack)
    if stack then
        stack = ItemStack(stack) -- Ensure it is an ItemStack
        if not stack:is_empty() then
            minetest.add_item(pos, stack)
        end
    end
end

local get_item_from_group     = function(groupString)
    if recycler.group_lookup[groupString] then
        local randkey = math.random(#recycler.group_lookup[groupString])
        return recycler.group_lookup[groupString][randkey]
    end
    return ""
end

-- @todo is this useful?
local get_destroy_mode_recipe = function(stack)
    local itemname = stack:get_name()
    -- craft items don't get destroyed.
    if mintest.registered_craftitems[itemname] then
        return stack
    end
    if (recycler.default_trash) then
        stack:set_name(recycler.default_trash)
    end
    return stack
end

local get_first_normal_recipe = function(pos, stack)
    local itemname = stack:get_name()

    local meta = minetest.get_meta(pos)
    local destroyMode = (1 == meta:get_int("destroy_mode"))

    -- to recycle enchanted items and cursed.
    if minetest.get_modpath("mcl_grindstone") then
        if minetest.settings:get_bool("k_recyclebin.recycle_cursed") then
            itemname = mcl_grindstone.remove_enchant_name(stack)
        else
            local newstack = mcl_grindstone.disenchant(stack)
            if "" ~= newstack then
                itemname = newstack:get_name()
            end
        end
    end

    local recipe = nil

    -- find and cache
    if not recycler.recipe_cache[itemname] then
        local recipes = minetest.get_all_craft_recipes(itemname)
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

                    -- full grid or formless already fit
                    if tmp.width == 3 or tmp.width == 0 then
                        recycler.recipe_cache[itemname].recipe = table.copy(tmp.items)
                    else
                        -- shift index to fit a 3x3 grid
                        for k, itm in pairs(tmp.items) do
                            local colNum = math.floor((k - 1) / tmp.width)
                            local newK = k + (colNum * (3 - tmp.width))
                            recycler.recipe_cache[itemname].recipe[newK] = itm
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
            if destroyMode then
                stack = get_destroy_mode_recipe(stack)
            end

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

local hopper_mode_timer_start = function(pos)
    local timer = minetest.get_node_timer(pos)
    if not timer:is_started() then
        timer:start(recycler.hopper_mode_timeout)
    end
end

local hopper_mode_timer_stop  = function(pos)
    local timer = minetest.get_node_timer(pos)
    if timer:is_started() then
        timer:stop()
    end
end

-- attempt recycling
-- @param pos vector
-- @returns boolean
local do_recycle              = function(pos)
    -- reread at each run in case you use the /set command.
    local leftoverFreebiesChance = math.min(1.0, math.max(0.0, (tonumber(minetest.settings:get("k_recyclebin.leftover_freebies_chance") or 0.05))))
    local minPartialRecycleRatio = math.min(1.0, math.max(0.0, (tonumber(minetest.settings:get("k_recyclebin.partial_recycling_minimum_ratio") or 0.5))))
    local meta = minetest.get_meta(pos)
    local inv = meta:get_inventory()
    local stack = inv:get_stack(recycler.container_input, 1)
    if
        inv_is_empty(inv, recycler.container_input)
        or not inv_is_empty(inv, recycler.container_output)
    then
        -- might  be emptying output
        --print("do_recycle skip")
        return false
    end

    local recipe, recipeOutput, idealOutputCount = get_first_normal_recipe(pos, stack)

    if idealOutputCount < 1 then
        return false
    end

    -- determine ratio of items we can recycle
    local idealInputStack = ItemStack(recipeOutput)
    local idealInputCount = idealInputStack:get_count()

    -- if in hopperMode, wait until a mimimum stack is available.
    if 1 == meta:get_int("hopper_mode") then
        -- bit messy wait logic to try and get a minimum usable stack.
        local hopperWaited = false

        if (meta:get_int("hopper_wait") > 0) then
            -- stack is driven by hopper abm at this point
            hopper_mode_timer_stop(pos)
            meta:set_int("hopper_wait", meta:get_int("hopper_wait") - 1)
            if meta:get_int("hopper_wait") == 0 then
                hopperWaited = true
            else
                -- print("wait 1 " .. meta:get_int("hopper_wait") .. " stack " .. stack:to_string())
                hopper_mode_timer_start(pos)
                return false
            end
        end

        if not hopperWaited and stack:get_count() < idealInputStack:get_count() then
            -- wait a bit more than min amount of extra items to push.
            meta:set_int("hopper_wait", idealInputStack:get_count() - stack:get_count())
            -- print("wait 2 " .. meta:get_int("hopper_wait") .. " stack " .. stack:to_string())
            -- does not not have a full stack and hopper could be out of items
            -- start timer again.
            hopper_mode_timer_start(pos)
            return false
        else
            meta:set_int("hopper_wait", 0)
        end
    end

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

        if math.random() <= remainderFreebieChance then
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
    if minPartialRecycleRatio > (remainderItemsStackSize / idealInputCount) then
        -- some leftovers may be discarded.
        local leftoverStack = ItemStack(recipeOutput)
        leftoverStack:set_count(remainderItemsStackSize)
        -- pop the rest
        pop_excess(pos, inv:add_item(recycler.container_output, leftoverStack))
    else
        -- randomize remainders
        local recipeKeys = {}
        for i, v in pairs(recipe) do
            if v ~= "" then
                table.insert(recipeKeys, i)
            end
        end
        table.shuffle(recipeKeys)

        -- shoud always be an item in there and remainder is less than idealOutputCount
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

        meta:set_int("hopper_mode", 0)
        meta:set_int("hopper_wait", 0)
        meta:set_int("destroy_mode", 0)
        meta:set_string("formspec", get_recycler_formspec(pos))
    end,


    on_receive_fields = function(pos, formname, fields, sender)
        -- print("on_receive_fields: " .. dump(formname) .. ", " .. dump(fields))
        local meta = minetest.get_meta(pos)
        if fields.hopper_mode then
            if "true" == fields.hopper_mode then
                meta:set_int("hopper_mode", 1)
            else
                meta:set_int("hopper_mode", 0)
            end
        end

        if fields.destroy_mode then
            if "true" == fields.destroy_mode then
                meta:set_int("destroy_mode", 1)
            else
                meta:set_int("destroy_mode", 0)
            end
        end

        -- refresh formspec
        meta:set_string("formspec", get_recycler_formspec(pos))
    end,

    after_dig_node = function(pos, oldnode, oldmetadata, digger)
        if not oldmetadata.inventory then return end
        for _, listname in ipairs({ recycler.container_input, recycler.container_output }) do
            if oldmetadata.inventory[listname] then
                for _, stack in ipairs(oldmetadata.inventory[listname]) do
                    pop_excess(pos, stack)
                end
            end
        end
    end,

    on_destruct = function(pos)
        local meta = minetest.get_meta(pos)
        meta:set_string("formspec", "")
        meta:set_int("hopper_mode", 0)
        meta:set_int("hopper_wait", 0)
        meta:set_int("destroy_mode", 0)
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
                minetest.log("info", string.format("Recylebin: %s recycled %s.", player:get_player_name(), stack:to_string()))
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
    on_timer = function(pos, elapsed)
        if (1 == minetest.get_meta(pos):get_int("hopper_mode")) then
            local loops = math.ceil(elapsed / recycler.hopper_mode_timeout)
            for i = 1, loops, 1 do
                do_recycle(pos)
            end
        end
    end
}

-- facedeer/tenplusone hoppers
if minetest.get_modpath("hopper") then
    hopper:add_container({
        { "top",    "k_recyclebin:recyclebin", recycler.container_output },
        { "bottom", "k_recyclebin:recyclebin", recycler.container_input },
        { "side",   "k_recyclebin:recyclebin", recycler.container_input },
    })
end

-- minetest
if minetest.get_modpath("default") then
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
elseif minetest.get_modpath("mcl_util") then
    thedef.sounds = mcl_sounds.node_sound_metal_defaults()

    thedef._on_hopper_in = function(hopper_pos, to_pos)
        local meta = minetest.get_meta(to_pos)
        local inv = meta:get_inventory()

        -- skip is in process of emptying or still processing
        if not inv_is_empty(inv, recycler.container_output) then
            --print("_on_hopper_in skip 1")
            return false
        end

        -- force hopper_mode off in mineclonia if connected to a hopper
        meta:set_int("hopper_mode", 1)
        meta:set_string("formspec", get_recycler_formspec(to_pos))

        local hopperInv = minetest.get_meta(hopper_pos):get_inventory()
        local slotId = mcl_util.get_first_occupied_inventory_slot(hopperInv, "main")

        if not slotId then
            return false
        end

        local hopperStack = hopperInv:get_stack("main", slotId)

        if not hopperStack then
            return false
        end

        local inputStack = inv:get_stack(recycler.container_input, 1)

        -- skip is in process of loading items
        if
            not inv_is_empty(inv, recycler.container_input)
            and hopperStack:get_name() ~= inputStack:get_name()
        then
            --print("_on_hopper_in skip 2")
            return false
        end

        local _, recipeOutput, _ = get_first_normal_recipe(to_pos, hopperStack)
        local idealRecipeStack   = ItemStack(recipeOutput)

        local sucked             = false
        -- try to load at least one stack if available
        if inputStack:get_count() < idealRecipeStack:get_count() then
            for i = 1, idealRecipeStack:get_count() - inputStack:get_count(), 1 do
                sucked = mcl_util.move_item_container(hopper_pos, to_pos, nil, nil, recycler.container_input)
            end
        end

        -- manually trigger recycle
        do_recycle(to_pos)

        return sucked
    end

    thedef._on_hopper_out = function(from_pos, hopper_pos)
        -- Suck items from the container into the hopper
        local sucked = mcl_util.move_item_container(from_pos, hopper_pos, recycler.container_output)

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
