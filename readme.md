# Minetest - Actual Recyclebin

Recycles things. Because having a lava pool around just to destroy trash is an OSHA violation. I keep picking up horse armor and I don't even have a horse.

Works with minetest base game and mineclonia but built mostly because of miclonia. Won't support mineclone2 since it's a bit outdated and the cherry blossom trees look not so good in that one.


## Limitations, todos, and known bugs

### As usual, no warranty, liability for loss of etc.

This is me just poking around with mintest mods and this one is mostly usable for my tastes.
Other recycling mods exist but I haven't looked at them and have no idea if this is the socially acceptable way to go about this.
If you don't like it, don't use it.

Although, if you have a suggestion or bug report, create an issue on the github repo.

See LICENSE. Should be GPLv3.

### Ingredients defined as `group` will output to random craft item within that group.

Because the way lua tables works and how recipes are fetched, there doesn't seem to be a reliable way
to get the exact source materials from a craft that accepts any item belonging to a group.

This could be considered a feature - the recycled output is a denatured version of the original.

Note that what an item belonging to a group is cached at server creation time, when a mapping of group -> actual item is created.
That mapping is used for subtituting the `group:` in the recipe definition.

For example `group:coal` + `group:stick` = `torch`

in mineclonia, both ground coal and charcoal belong to `group:coal` and bamboo is also of `group:stick`

Recycling a torch crafted form coal and stick may yield any combination of (coal,charcoal)+(stick,bamboo) depending on what was cached/found at run time. 


### Recyling items that generate multiples.

The issue is that recipes sometimes produce stacks of items. 1 coal + 1 stick  = 4 torches. Which means that ideally, you'd want to enter a stack of 4 torches as input to get 1 stick and coal as output.

However you rarely have exact multiples of items. 

There's some change you'll get a full item if close enough to original stack. Because game logic. See `k_recyclebin.leftover_freebies_chance` settings to tweak it slightly or disable it.

Partial recycling is also available.

in `minetest` game, 6 wood blocks -> 8 wood stairs. To get back exactly 6 wood blocks you need to recycle a stack with 8 stairs. Or multiples thereof. The code currently tries to ratio the source:output quantities so that if you recycle 4 wood stairs, you can expect to get 3 wood blocks. There some randomness in there so you'll sometimes end up with 1 extra ingredients when the stack quantities aren't ideal factors.

Infinite item exploit. You're welcome.

The `k_recyclebin.partial_recycling_minimum_ratio` setting contols partial recycling somewhat. By default you need half a stack to allow partial recycling. If not, the item will just pass trough unchanged.

IMPORTANT: Note that passtrough currently can cause loss of source material if the output grid is full and there's no space to add the overflow. This is fine since the recycling bin is only supposed to be a way to reclaim some trash.

### Hoppers

For `mineclonia`, hoppers can be used to automate processing. A reasonable shematic would be Chest -> recycler -> chest where `->` is a hopper. That way you can dump all the loot you don't care about in the top chest and collect materials later.

The hopper should try to wait until a minimum stack is available but will eventually just push trough.


### Needs an off switch (mineclonia only)

TODO - When connected to hoppers, items sucked in are immediately processed and moved along. Might be good idea to have it pausable via redstone or switches.

