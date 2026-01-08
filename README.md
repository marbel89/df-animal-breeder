# gui/animal-breeder

A DFHack GUI for viewing animal attributes, body size modifiers, and managing selective breeding programs in Dwarf Fortress.

![DFHack](https://img.shields.io/badge/DFHack-50.xx+-green)
![Dwarf Fortress](https://img.shields.io/badge/Dwarf%20Fortress-50.08+-blue)
![License](https://img.shields.io/badge/license-MIT-blue)

## Overview

The vanilla DF animal screen doesn't expose attributes or body size modifiers, making selective breeding guesswork. This tool shows all hidden stats, tracks generations, and exports data for analysis.

**Key discovery from using this tool:** Attributes (STR, AGI, etc.) don't inherit, but body size modifiers (HEIGHT, BROADNESS, LENGTH) do inherit weakly (r ≈ 0.2-0.4). See [Research Findings](#research-findings) below.

## Features

### Animal Stats Display
- **10 Attributes**: Strength, Agility, Toughness, Endurance, Recuperation, Disease Resistance, Willpower, Focus, Spatial Sense, Kinesthetic Sense
- **Body Size Modifiers**: Height, Broadness, Length (as % of species baseline)
- **Lineage**: Mother ID, Father ID (when tracked by DF)
- **Generation**: Automatically calculated (F0, F1, F2, etc.)

### Display Modes

**Vague Mode** (default) - Compact symbols for quick and immersive scanning:
```
+++  Exceptional (≥+750 from median)
++   Great      (≥+400)
+    Good       (≥+150)
~    Average    (±150)
-    Poor       (≤-150)
--   Bad        (≤-400)
---  Terrible   (≤-750)
```

**Detailed Mode** - Full numeric values for all stats, if you want to peep behind the curtains.

### Herd Management
- Sort by any column (click headers)
- Filter by name or tag
- Multi-select with Shift+Click
- Bulk actions: Cage, Butcher, Geld
- Assign custom names and tags (e.g., `[KEEP]`, `[BREED]`, `[CULL]`)

### Data Export
- Export current species to CSV
- Custom filename prompt
- Includes all stats, parent IDs, generation, status flags

## Installation

### Manual Installation

1. Download `gui/animal-breeder.lua`
2. Place in your DFHack scripts directory:
   - Windows: `Dwarf Fortress/hack/scripts/gui/`
   - Linux: `~/.dwarffortress/hack/scripts/gui/`
   - macOS: `~/Library/Application Support/Dwarf Fortress/hack/scripts/gui/`

### Hotkey Binding (Optional)

Add to `dfhack-config/init/onMapLoad.init`:
```
keybinding add Alt-B gui/animal-breeder
```

## Usage

### Basic Commands

```bash
gui/animal-breeder          # Open in vague mode (default)
gui/animal-breeder -d       # Open in detailed mode
gui/animal-breeder --detailed
```

### Status Indicators
- `C` - Caged
- `Zn` - Assigned to zone/pasture  
- `Gld` - Gelded
- `B` - Marked for butcher

### Keyboard Shortcuts

| Key | Action |
|-----|--------|
| `↑/↓` | Navigate list |
| `Enter` | Toggle mark selection |
| `Shift+Click` | Multi-select range |
| `C` | Cage marked animals |
| `B` | Mark for butcher |
| `G` | Geld marked animals |
| `E` | Export to CSV |
| `N` | Set name |
| `T` | Set tag |
| `V` | Toggle vague/detailed mode |
| `Esc` | Close |

## CSV Export Format

```csv
ID,Race,Sex,Adult,Gelded,Caged,Slaughter,Name,Tag,Mother_ID,Father_ID,STR,AGI,TGH,END,REC,DIS,WIL,FOC,SPA,KIN,PHYS_AVG,PHYS_PCT,MENT_AVG,MENT_PCT,ALL_AVG,ALL_PCT,HERD_RANK,BODY_HEIGHT,BODY_BROADNESS,BODY_LENGTH,BODY_SIZE_PCT,Generation
11797,RABBIT,F,Y,N,N,N,Bessie,[KEEP],-1,-1,1204,1005,1146,759,1830,1077,893,1001,1140,1054,1189,78,1033,55,1111,67,12,92,101,108,100,0
```

## Research Findings

**Conclusion:** Attributes are randomly assigned at birth. Don't bother selecting for them as of now.

**Conclusion:** Body size modifiers do inherit (r ≈ 0.2-0.4). Breeding larger animals produces slightly larger offspring.


## Known Issues

- **Zone unassignment**: Caging animals doesn't automatically unassign them from pastures. Unassign manually first.
- **Father tracking**: Some species (rabbits) don't track paternity. Father_ID will be -1.
-  Well, the feature of attribute inheritance needs to be patched in, to begin with...

## Future features

- Get Werner Herzog to narrate animal and dwarf behavior

## Requirements

- Dwarf Fortress 50.08+
- DFHack 50.08-r1+


## License
MIT License - see [LICENSE](LICENSE)
