# Minetest - Actual Recyclebin

Recycles things, assuming there exists a crafting recipe for it. Because having a lava pool around just to destroy trash is an OSHA violation.

Works with minetest base game and mineclonia but built mostly because of mineclonia. It might work with mineclone2 but not officially supported.

## Crafting the recyclebin

In `minetest`, you'll need steel ingots, diamond block, furnace, and chest to unlock the recipe.

In `mineclonia`, you'll need iron ingots, redstone block, furnace, composter, crafting table, and chest to unlock the recipe.

`minetest` and `mineclonia` have different recipes for no reason other than aesthetics.

## Usage

`Place/use` (usually right click) a placed recycle bin to open the UI.

Left single slot accepts the input, output preview will appear in rightmost 3x3 grid. Your inventory should be in the bottom.

You can  cancel the recycle operation by removing the input item. However,  taking an item from the 3x3 grid into your main inventory will count as confirming the recycle operation and destroy the input item.

### Unrecyclable items

Items that can't be broken down, i.e do not have a crafting recipe, or have insufficient stack size will simply "pass through" the recycle bin and appear unchanged in the output grid.

The recycle bin will try not to destroy unrecyclable input items (mostly) so you might want to keep that lava pool around.

### Recyling items that generate stacks of multiple items.

Recipes often produce stacks of items. 1 coal + 1 stick  = 4 torches. Which means that ideally, you'd want to enter a stack of 4 torches as input to get 1 stick and coal as output.

However you rarely have exact multiples of items. The recycle bin addresses that by allowing for "Partial recycling".

For example in `minetest` game, 6 wood blocks -> 8 wood stairs. To get back exactly 6 wood blocks you need to recycle a stack with 8 stairs. Or multiples thereof. The code currently tries to ratio the source:output quantities so that if you recycle 4 wood stairs, you can expect to get 3 wood blocks. Due to rounding, you'll sometimes end up with 1 extra/less ingredients when the stack quantities aren't ideal factors.

The `k_recyclebin.partial_recycling_minimum_ratio` setting contols partial recycling somewhat. By default, it has a value of `0.5`, which means you need at leart half a full input stack to allow partial recycling. So if you supply 2 torches you will end up with either 1 coal or 1 stick. But recycling only 1 torch will most likely pass through unchanged.

### Freebies

Another "feature" of this recyling bin is allowing freebies when recycling partial stacks.  There's some none zero change (default is less than 5%) you'll get a full item if close enough to original stack. So a stack of 3 torches can give you a full 1 coal + 1 stick.

Infinite item exploit. You're welcome. Well not really, it's basically a gamble if you'll get a free item and it's usually faster to just mine/farm things. But it's a little more fun if there's some randomness involved. See `k_recyclebin.leftover_freebies_chance` settings to tweak it slightly or disable it.

### Hopper support

Supports `mineclonia` hopper API and the [FaceDeer hopper mod](https://content.minetest.net/packages/FaceDeer/hopper/). Well, as long as you don't look at the inner workings too closely, it's usable.

Hoppers can be used to automate processing. A reasonable shematic would be Chest -> recycler -> chest where `->` is a hopper. That way you can dump all the loot you don't care about in the top chest and collect materials from the bottom one later.

The recycle bin should try to wait until a minimum ideal stack of items is available but will eventually just push trough. So if you put a stack of 7 torches in the input hopper, it will wait until 4 torches are loaded in the recycle bin and then trigger a recyle and flush out items to output hopper. For the remaning 3 torches, it will wait an few extra ticks in case additional items are being added but will just try to recycle that stack of 3, resulting in either a partial recycle or a freebie if lucky.

Note that not all edge cases with hoppers have been discovered or even considered. Stack of items may still not get fed in properly. Single stack items like weapons, armor, tools get processed just fine though.

When using `mineclonia`, the recyclebin will automatically detect if connected to a hopper and enter something called `Hopper Mode`. When using the `hopper` mod, you will have to manually check the `Hopper Mode` checkbox in the recyle bin UI after connecting it to hoppers. Note that you can use `Hopper mode` without connecting to hopper but all that does is add an awkward 3 seconds delay before processing what ever stack of item you manually input.

The `hopper` mod simulates a player moving the items one at a time and I haven't found a reliable way to determine if it's a player doing the item adding or if it's the hopper in order to wait for a minimum stack. And rather than replicating the logic from the ABM definition to figure out which hopper is connected to what, I just added the manual check. `mineclonia`'s hopper API is more manual and allows for more ~~hacky workarounds~~ finetuning and control.



## Limitations, todos, and known bugs

### As usual, no warranty, liability for loss of etc.

This is me just poking around with mintest mods and this one is mostly usable for my tastes.
Other recycling mods exist but I haven't looked at them and have no idea if this is the socially acceptable way to go about this.
If you don't like it, don't use it.

Although, if you have a suggestion or bug report, create an issue on the github repo.

See LICENSE for forking/reuse. Should be GPLv3.

### Ingredients defined as `group` will output to random craft item within that group.

Because the way lua tables works and how recipes are fetched, there doesn't seem to be a reliable way
to get the exact source materials from a craft that accepts any item belonging to a group.

This could be considered a feature instead of a bug - the recycled output is a denatured version of the original.

Note that what items belonging to a group is cached at server creation time - a mapping of group -> actual item is created.
That mapping is used for subtituting the `group:...` values in the recipe definition.

For example, assume the following recipe exists `group:coal` + `group:stick` = `torch` and coal and charcoal belong to `group:coal` and stick and bamboo are in `group:stick`

Recycling a torch crafted form coal and stick may yield any combination of `(coal,charcoal)+(stick,bamboo)` depending on what was cached/found at run time. 

### Destroy Mode (WIP; disabled by default)

There are occasionally items that can't be crafted and therfore recycled but you still don't want to keep them around. Or they may be leftovers from another mod you disabled and they show up as unknown blocks or items in your inventory. Or just stuff you really don't care to keep around.

"Destroy Mode" is an attempt at trying to recover something out of those items. However, currently it just destroys those items to lumps of coal, which turns the recycle bin into an incinerator basically.

Use `k_recyclebin.destroy_mode_enable` setting to enable it.

