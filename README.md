# Animal Breeder for DFHack
   
   A GUI tool for managing animal breeding in Dwarf Fortress.
   
   ## Installation
   1. Copy `animal-breeder.lua` to `<DF>/hack/scripts/`
   2. In-game, run: `animal-breeder`
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

## Known bugs:
- Copy to clipboard does not properly format
- Sometimes the GUI pops up during loading
