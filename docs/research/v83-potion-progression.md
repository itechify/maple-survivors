# v83 town-shop potion progression for Lv 1-70 (ticket #227, spec #225)

Question: which HP and MP potions do v83 town shops sell to a Lv 1-70 character, what do they restore and cost, and at
what level did players usually switch to each? The answer feeds the automatic potion schedule
(`game/data/survivor/balance.json` `potions.schedule`, ticket #229). Elixir (2000004) and Power Elixir (2000005) are
excluded by the owner; they stay the job-neutral filler card of spec #225.

Evidence tiers follow `docs/GAME_DESIGN.md` "Constants and provenance": **A** = verified in the player's own v83 data,
**B** = third-party reconstruction of an official server, **C** = community lore or our own choice. Nothing here is
copied WZ data; only item ids, numbers and names as facts.

## Summary

- **Item numbers are tier A.** Every id, recovery, price and name below was read from the local v83 `Item.wz`
  (`Consume/0200.img`, `0201.img`, `0202.img`) and `String.wz` (`Consume.img`). The ids 2000000-2000006 were also
  checked in the asset cache (`Item.wz/Consume/0200.img.json`); the cache only keeps those seven, so the rest was
  read from the original archives with a read-only explorer.
- **Shop contents are tier B/C.** Shop stock is server-side and is not in the WZ files. The only full list we have is
  the shop data of Cosmic (v83 private-server reconstruction), which runs on edited WZ files, so treat it as a
  reconstruction. Two points were corroborated independently (Section 4).
- **Shop price is 2x the WZ `info/price`** for the common potions in the Cosmic data (50 vs 25, 160 vs 80, 620 vs 310,
  1100 vs 550, 1650 vs 825, 2300 vs 1150, 4000 vs 2000; Reindeer Milk is the one near-miss, 5600 vs 5500). A 2011 MapleSEA player guide quotes Orange about 160, White
  about 320, Mana Elixir 590-620, Unagi 1100 and Pure Water 1600-1700 mesos, which matches the 2x column (Section 3), so
  the WZ `price` is the base value, not what the player pays.
- **Switch levels are thin tier C.** No period guide with an exact level per potion was reachable. What exists: one
  retrospective seller blog (Orange 15-35, White 30+, Mana Elixir 30+), a BasilMarket guide that ties the choice to
  max HP/MP (Unagi, Pure Water, Mana Elixir for 800-1500), and a wiki line that White Potion, Unagi and Pure Water
  open up after a Lv 40 quest. The proposed levels in Section 6 are our own reading of these plus the game's HP/MP
  pools, not a quoted community number.
- **Proposed schedule:** keep hp Orange @10, mp Mana Elixir @20, hp White @25, and add Unagi and Pure Water @40, and
  the 2000-point foods (Ice Cream Pop, Red Bean Sundae) @60 as optional last steps. The El Nath 4000-5000 items stay out
  of the schedule.
- **Unchecked:** exact v83 shop stock per town, the real switch levels, and whether Chocolate is a v83 shelf item
  (Section 8).

## 1. Candidate items (tier A: local v83 `Item.wz` + `String.wz`)

HP/MP restoring consumables that a v83 shop sells and whose recovery is a flat `hp` or `mp` amount. Percent items
(Elixir `hpR`/`mpR`) and items that restore both pools are not usable as a single-kind step and are listed separately.

| Id | Name (String.wz) | Restores | WZ `info/price` | Cosmic shop price |
|---|---|---|---|---|
| 2000000 | Red Potion | 50 HP | 25 | 50 |
| 2000001 | Orange Potion | 150 HP | 80 | 160 |
| 2000002 | White Potion | 300 HP | 160 | 320 |
| 2022003 | Unagi | 1000 HP | 550 | 1100 |
| 2001001 | Ice Cream Pop | 2000 HP | 1150 | 2300 |
| 2020012 | Melting Cheese | 4000 HP | 2250 | 4500 |
| 2020013 | Reindeer Milk | 5000 HP | 2750 | 5600 |
| 2000003 | Blue Potion | 100 MP | 100 | 200 |
| 2000006 | Mana Elixir | 300 MP | 310 | 620 |
| 2022000 | Pure Water | 800 MP | 825 | 1650 |
| 2001002 | Red Bean Sundae | 2000 MP | 2000 | 4000 |
| 2020014 | Sunrise Dew | 4050 MP in `spec`; its String.wz text says 4000 | 4050 | 8100 |
| 2020015 | Sunset Dew | 5000 MP | 5100 | 10200 |

Notes on the table:

- Ice Cream Pop and Red Bean Sundae have String.wz descriptions "Recovers around 2000 HP/MP" and `spec` 2000, read from
  the same files.
- Cosmic prices are given for the standard shop (Orbis, Edel). A few other shops add or remove about 4-5 % (Ludibrium and
  Omega Sector about 5 % less, El Nath Ice Valley II about 4 % more), and Reindeer Milk is 5600 against 2 x 2750 = 5500,
  so 2x is the rule for the common items, not for every row.
- Sunrise Dew: the `spec` value (4050) and the description (4000) disagree in v83 data. #229 should read `spec`, since
  that is what the game applies, and may mention the oddity.
- Food with an extra weakness is irrelevant here: Red Bean Porridge (2022001) and Cider (2022002) are buffs, not
  restoratives.
- Dual-pool or percent items, skipped as non-single-kind: Elixir 2000004 (50%/50%), Power Elixir 2000005 (100%/100%),
  Watermelon 2001000 (1000 HP + 1000 MP), Cake 2020002 (100 + 100), Chocolate 2020028 (1000 + 1000). Small foods
  (Apple 30 HP, Egg 50 HP, Meat 100 HP, Orange 50 MP, Lemon 150 MP, Fried Chicken 200 HP, Salad 200 MP, Hot Dog 300,
  Pizza/Hamburger 400, Hot Dog Supreme 500 HP) are below or equal to White Potion and are not a progression.
- Pills (Red/Orange/White/Blue Pill 2000007-2000010, Mana Elixir Pill 2000011) restore the same amounts as the potions
  but stack to 150 and are only sold in Ludibrium; they are not a new tier.
- Beginner, event and Noblesse potions (2000013-2000023, `notSale` or `tradeBlock`) are not shop stock.

## 2. Which shops sell each potion (tier B/C: Cosmic shop data)

Source: the shop tables of Cosmic (v83 private-server reconstruction); shop id = NPC id. NPC names and the map each NPC
stands in were read from the local `String.wz` and `Map.wz` (tier A for "this NPC stands in this map"). Only the shops
a Lv 1-70 character plausibly uses are listed.

| Potion | Sold in (town, NPC) |
|---|---|
| Red, Orange, White, Blue | every shop in the rows below (Victoria Island department stores, Sleepywood, Florina Beach, Ereve, Rien, Nautilus, Orbis, El Nath, Ludibrium and later towns); Amherst (Lucy) sells Red/Orange/White only; El Nath Ice Valley II (Glibber) has no Red, and Amherst has no Blue |
| Mana Elixir 2000006 | Lith Harbor (Mina), Henesys (Luna), Perion (Arturo), Ellinia (Len), Kerning City Pharmacy (Dr. Faymus), Sleepywood Regular Sauna (Mr. Sweatbottom), Nautilus (Gali), Ereve (Kiriwing), Rien (Puri Puri), Orbis (Edel), El Nath (Hana), Ludibrium Pharmacy (Misky), Omega Sector (Dr. Pepper), Aquarium (Oannes), Korean Folk Town, Leafre, Mu Lung, Herb Town, Ariant, Magatia |
| Unagi 2022003 | Sleepywood Regular Sauna (Mr. Sweatbottom), Florina Beach (Valen), Orbis (Edel), El Nath (Hana, Glibber), Ludibrium (Eos Tower, Path of Time), Omega Sector, Aquarium, Korean Folk Town, Mu Lung, Herb Town, Ariant, Magatia, Altaire Camp |
| Pure Water 2022000 | same shops as Unagi |
| Ice Cream Pop 2001001, Red Bean Sundae 2001002 | Florina Beach (Valen), Orbis (Edel), El Nath (Hana, Glibber), Ludibrium Pharmacy and Eos Tower, Omega Sector, Aquarium, Korean Folk Town, Leafre, Mu Lung, Herb Town, Ariant, Magatia, Altaire Camp |
| Melting Cheese, Reindeer Milk, Sunrise Dew, Sunset Dew | El Nath (Hana in the department store, Glibber in Ice Valley II), Ludibrium (Eos Tower, Path of Time), Omega Sector, Aquarium, Korean Folk Town, Leafre, Mu Lung, Altaire Camp |

Reading the table: Victoria Island's first-job towns only ever sell the Red/Orange/White and Blue/Mana Elixir tiers.
Unagi and Pure Water appear first in Sleepywood (Lv 30-40 content), the 2000-point foods in Florina Beach, Orbis and
beyond, and the 4000-5000 items only in El Nath and farther. Cosmic stocks Chocolate (2020028) in many first-job towns;
that looks like an event item rather than v83 shelf stock and is not used here.

## 3. Prices cross-check (tier C, period)

"Save MapleStory Mesos" (MapleSEA player blog, 2011, fetched in full) quotes: Orange 150 HP for about 160 mesos, White
300 HP for about 320, Mana Elixir 300 MP for about 590-620, Unagi 1000 HP for about 1100, Pure Water 800 MP for about
1600-1700. These match the Cosmic/2x column in Section 1.
<http://maplesecrets.blogspot.com/2011/08/save-maplestory-mesos-how-to-save-mesos.html>

## 4. Independent corroboration of shop locations (tier C)

- The Wikibooks "MapleStory/Use Items" page lists Unagi and Pure Water at the Regular Sauna in Sleepywood, the Red/Orange/
  White/Blue Pill and Mana Elixir Pill at the Ludibrium Potion Store, and Red/Orange/White/Blue/Mana Elixir at "most
  department stores". That agrees with Cosmic shops 1061002, 2041006 and the department-store rows. It also says Jane
  the Alchemist sells White Potion, Unagi and Pure Water "after the level 40 quest".
  <https://en.wikibooks.org/wiki/MapleStory/Use_Items>
- A MapleStory Classic item database page (a different, later release with different numbers, used here for the shop
  only) lists Red Bean Sundae as sold by Valen in Florina Beach, matching Cosmic shop 1081000 (search-result excerpt,
  page not read in full). <https://meowdb.com/msclassic/item-db/260>
- The same database lists Melting Cheese's sellers as Glibber in El Nath: Ice Valley II, matching Cosmic shop 2030009
  (search-result excerpt). <https://meowdb.com/msclassic/es/item-db/2558>

## 5. When players switched (tier C, thin)

| Source | Version / trust | What it says |
|---|---|---|
| "Potions in Old Maple, What to Buy at Every Level" <https://msclassicgold.com/blog/potions-in-old-maple> (fetched) | Seller blog, "from memory", approximate, low trust | Red Potion for Lv 1-15; Orange Lv 15-35 for most classes; White Lv 30+ ("the warrior's staple"); Blue Potion for Magicians to about Lv 30; Mana Elixir for mages from Lv 30 and any class with a booster; Elixirs/Power Elixirs for bosses only; Magicians barely buy HP potions once Magic Guard is up |
| BasilMarket potion guides (search-result excerpts; the pages returned HTTP 522, so the wording is as excerpted) <http://www.basilmarket.com/forum/1142354/0/Potion_Guide.html>, <http://www.basilmarket.com/forum/2443651/10/Dual_Blade_Guide.html> | Post-Big-Bang era forum guides for mages and a Dual Blade; same items | Lv 30-60: White Potions or Unagi for HP, Pure Water (or Sunrise Dew) for MP; for max HP or MP of 800 to 1,500 use Unagi, Pure Water, Mana Elixir |
| Wikibooks "MapleStory/Use Items" <https://en.wikibooks.org/wiki/MapleStory/Use_Items> (fetched) | Community wiki | White Potion, Unagi and Pure Water are sold by Jane the Alchemist after a Lv 40 quest |
| "Save MapleStory Mesos" 2011 <http://maplesecrets.blogspot.com/2011/08/save-maplestory-mesos-how-to-save-mesos.html> (fetched) | MapleSEA player blog | Beyond Lv 20 "it's nearly impossible to train without using potions"; mentions a few White potions/Unagis for Zakum PQ part 1 |
| Classic consumables guide <https://metaroad.gg/maplestory-classic/walkthroughs/the-complete-consumables-guide> (fetched) | **MapleStory Classic, not v83** (Orange is 250 HP there) | Red stops making sense once max HP passes about 600-800; shown only as a hint on the max-HP rule of thumb, not used for levels |

Conclusions:

1. The only level numbers are from the seller blog (15 / 30 / 30). They are later than the existing owner-settled steps
   (Orange @10, White @25, Mana Elixir @20). **Per the ticket these existing levels are not proposed for change**; the
   gap is noted only so nobody mistakes the existing levels for the community's.
2. For Unagi and Pure Water the earliest level signal is the Lv 40 mark (Wikibooks) and the Lv 30-60 band
   (BasilMarket, 800-1500 max HP/MP). Lv 40 is inside both.
3. No source says when anyone switched to Ice Cream Pop, Red Bean Sundae or the El Nath foods; they are a shop-based
   extrapolation, not lore. They would be used by players with a pool of roughly 2000 or more.

## 6. Proposed schedule (tier C)

Steps are `{level, kind, item}`, ascending level, monotonic per kind (each step restores strictly more). "Existing"
steps are the owner-settled ones that #228 ships; "new" steps are the proposal for #229. Starting items are Red Potion
(hp) and Blue Potion (mp).

| Level | Kind | Item | Restores | Status |
|---|---|---|---|---|
| 10 | hp | 2000001 Orange Potion | 150 | existing |
| 20 | mp | 2000006 Mana Elixir | 300 | existing |
| 25 | hp | 2000002 White Potion | 300 | existing |
| 40 | hp | 2022003 Unagi | 1000 | **new** |
| 40 | mp | 2022000 Pure Water | 800 | **new** |
| 60 | hp | 2001001 Ice Cream Pop | 2000 | **new, optional** |
| 60 | mp | 2001002 Red Bean Sundae | 2000 | **new, optional** |

Why these and not more:

- Unagi and Pure Water are the first tier past White Potion and Mana Elixir: sold from Sleepywood (Lv 30-40 content), both named in the
  period guides, and the next real jump (3.3x and 2.7x). Lv 40 is inside the BasilMarket band and at the Wikibooks quest
  level.
- Ice Cream Pop and Red Bean Sundae are real shelf items of Florina Beach, Orbis and El Nath, but nothing in the
  sources says when players moved to them (Section 5 point 3). Lv 60 is our own pick: near the top of the range where
  they are sold in Orbis/El Nath and past the BasilMarket Lv 30-60 band. They are marked optional because the pool
  numbers below show they restore more than any job's whole pool for most of Lv 40-70.
- Melting Cheese (4000), Reindeer Milk (5000), Sunrise Dew (4050) and Sunset Dew (5000) are **not proposed**. They
  are El Nath-and-later stock and exceed every job's maximum HP/MP in range. Sunrise/Sunset Dew are the BasilMarket
  excerpt's "Pure Water or Sunrise Dew" for mage MP, so if the owner wants a Lv 70 MP step the candidate is Sunset Dew
  2020015 @70; there is no source for an HP step beyond Ice Cream Pop.
- Percent/dual-pool foods (Watermelon, Chocolate, Cake) and the Elixirs are out by the ticket's definition.

### How the restores compare with the game's own pools

The survivor mode raises max HP with the job's `growth` table (`balance.json` `growth`; `docs/GAME_DESIGN.md` section on
stats per level; level-ups refill MP but add no HP). Base max HP is about `50 + g x (Lv - 1)` with g = Magician 12,
Bowman and Thief 22, Pirate 25, Warrior 26 (Beginner 14 before the first job), before equipment and Improved MaxHP:

| Lv | Magician | Bowman/Thief | Pirate | Warrior |
|---|---|---|---|---|
| 40 | 518 | 908 | 1025 | 1064 |
| 50 | 638 | 1128 | 1275 | 1324 |
| 60 | 758 | 1348 | 1525 | 1584 |
| 70 | 878 | 1568 | 1775 | 1844 |

Real bot-character fixtures (`game/tests/fixtures/characters/`) show the formula is a floor for lines with HP skills or
gear: Lv 34 Fighter `base_hp` 1350, Lv 50 Bandit 1506, Lv 38 Magician 512 (formula 494), Lv 30 Hunter 1066. Max MP of
the same fixtures: Lv 38 Magician `base_mp` 1019, Lv 50 Bandit 695, Lv 37 Brawler 648, Lv 34 Fighter 215. Consequences:

- A 1000-HP Unagi at Lv 40 is a nearly full heal for a Magician (518 base HP) and for Bowman/Thief lines; a Warrior
  uses it better. That is the same overheal the 300-HP White Potion has for a Lv 25 Magician today; BasilMarket's
  800-1500 guidance would put the sensible Unagi switch at 800+ max HP, which for the Magician is not before Lv 60.
- An 800-MP Pure Water at Lv 40 fits a Magician (1019+) but is more than a Fighter's or Brawler's whole MP pool.
- A 2000-point step is larger than every non-Warrior pool until about Lv 70.

The schedule is job-agnostic by spec #225, so #229 and the owner should decide whether to accept the overheal or to
hold the big steps back; the numbers above are the input.

## 7. Asset needs for the new steps

`String.wz/Consume.img` is exported **whole** (`asset_manifest.json`: `{"img": "String.wz/Consume.img"}`), so every
name and description is already in the cache. Nothing to add for strings.

Icons and restore specs: `asset_manifest.json` `items[]` lists ids individually and currently holds 2000000-2000006
among its entries; `asset_manifest.d/common.json` has `"items": []`. The importer exports `Item.wz/Consume/<id/10000>.img/<id>`
(including `info/icon` and `spec`, as the cache's `0200.img.json` shows). The new ids are therefore **not** exported
yet. #229 appends them to `items[]` in `game/data/asset_manifest.json` (not to `common.json`: duplicates across
manifest files are an error):

| Id | Img the importer reads | Present in the manifest today |
|---|---|---|
| 2022003 Unagi | `Item.wz/Consume/0202.img` | no |
| 2022000 Pure Water | `Item.wz/Consume/0202.img` | no |
| 2001001 Ice Cream Pop | `Item.wz/Consume/0200.img` | no |
| 2001002 Red Bean Sundae | `Item.wz/Consume/0200.img` | no |

Use sounds: the manifest selects `Sound.wz/Item.img` `02000000/Use` through `02000006/Use`. The new ids have their own
`Use` nodes: `02001001/Use`, `02001002/Use` and `02022003/Use` are Sound nodes, while `02022000/Use` (Pure Water) is a
link to `../02012002/Use`, which is outside the selected set. Missing sounds stay silent and show up in the playtest
`missing` list; if the owner wants the sound, add the four `Use` paths and check that the importer resolves the Pure
Water link. #229 changes the manifest, so it imports into its own private cache
(`MAPLE_SURVIVORS_CACHE=<dir>`), per `AGENTS.md`.

`PotionInventory.upgrade(kind, item)` only accepts an item whose `spec.<kind>` is above zero, so each of the four new
items resolves through the `setup.item_info` entries the importer builds from `Item.wz` once exported.

## 8. What could not be checked

- **Exact v83 shop stock per town.** Shop lists are server-side. The Cosmic tables are a private-server reconstruction
  that runs on edited WZ files; they were cross-checked only for Sleepywood (Unagi, Pure Water), the Ludibrium pills
  and Florina Beach (Red Bean Sundae), and for the 2x price rule against a 2011 MapleSEA blog. Everything else in
  Section 2 rests on that one source (tier B/C).
- **Real switch levels.** No primary-era forum page with a per-level answer could be read; the BasilMarket pages
  returned HTTP 522 (excerpts only). Treat Section 5 and the schedule levels as tier C.
- **Chocolate (2020028)** in first-job town shops: probably not a GMS v83 shelf item; unverified and unused.
- **Sunrise Dew's real value** (4050 in `spec`, 4000 in its description): both are in the local data; which one the
  v83 client applies is unverified.
- Everything in Section 1 other than the listed Cosmic shop prices was read from the local v83 data (checked).
