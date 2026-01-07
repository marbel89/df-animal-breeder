# Animal Breeder for DFHack
   
   A GUI tool for managing animal breeding and attribute hereditary in Dwarf Fortress... if it were implemented.
   
   ## Installation
   1. Copy `animal-breeder.lua` to `<DF>/hack/scripts/`
   2. In-game, run: `animal-breeder` via DFHack
   3. Optional: Add to `dfhack-config/init/onMapLoad.init`:
```
      keybinding add Alt-B animal-breeder
```
   
   ## Features
   - View all 10 attributes with color coding
   - Percentile rankings within species
   - Filter by sex, age, gelded, caged
   - Batch operations: Tag, Geld, Cage, Butcher
   - CSV export

## Future features
   - From a gameplay point of view, the exact attributes stats should probably be obfuscated and only ingame data should be used (i.e. "strong", "good kinesthetic sense" and so on). For testing I had to know the exact stats, but it feels to gamey to look behind the curtains.
     - Well, the feature of attribute hereditary needs to be patched in, to begin with...
   - Get Werner Herzog to narrate animal and dwarf behavior

## Known bugs:
- Copy to clipboard does not properly format
- Sometimes the GUI pops up during loading
