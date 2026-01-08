-- GUI for managing animal breeding based on attributes and body size.
--[====[

gui/animal-breeder
==================

Tags: fort | animals | productivity

A GUI tool for managing animal breeding programs. Displays physical and mental
attributes with color-coding to identify breeding stock. Also shows body size
modifiers (height, broadness, length) which affect butcher yields and combat.

Allows mass caging of animals if you do not want to butcher them.

Note: Testing confirms that DF does NOT implement genetic inheritance for
attributes - offspring stats are random. However, body size DOES inherit. This tool helps manage populations and
select for body size in meat/war animals. And who knows if further inheritance gets patched in?

Usage
-----

::

    gui/animal-breeder [options]

Examples
--------

``gui/animal-breeder``
    Opens the GUI in vague mode (default) with DF-style trait descriptors.

``gui/animal-breeder --detailed``
    Opens the GUI showing exact numeric values for all attributes.

Options
-------

``--detailed``
    Show numeric attribute values instead of descriptive text.
    Default mode shows DF-style descriptors like "Strong" or "Very agile".

]====]

local gui = require('gui')
local widgets = require('gui.widgets')
local dlg = require('gui.dialogs')

-- Helper: Confirmation dialog that accepts Enter (not just Y/N)
local function showConfirm(title, message, on_yes)
    dlg.showListPrompt(
        title,
        message,
        COLOR_WHITE,
        {"Yes", "No"},
        function(idx, choice)
            if idx == 1 then
                on_yes()
            end
        end
    )
end

-- Session storage (persists until DF closes)
animal_breeder_last_species = animal_breeder_last_species or nil

-- Physical attributes
local PHYS_ATTRS = {'STRENGTH', 'AGILITY', 'TOUGHNESS', 'ENDURANCE', 'RECUPERATION', 'DISEASE_RESISTANCE'}
-- Mental attributes
local MENTAL_ATTRS = {'WILLPOWER', 'FOCUS', 'SPATIAL_SENSE', 'KINESTHETIC_SENSE'}
-- All attributes for filtering
local ALL_ATTRS = {'STRENGTH', 'AGILITY', 'TOUGHNESS', 'ENDURANCE', 'RECUPERATION', 'DISEASE_RESISTANCE', 
                   'WILLPOWER', 'FOCUS', 'SPATIAL_SENSE', 'KINESTHETIC_SENSE'}
-- Short names for display
local ATTR_SHORT = {
    STRENGTH='STR', AGILITY='AGI', TOUGHNESS='TGH', ENDURANCE='END', 
    RECUPERATION='REC', DISEASE_RESISTANCE='DIS',
    WILLPOWER='WIL', FOCUS='FOC', SPATIAL_SENSE='SPA', KINESTHETIC_SENSE='KIN',
    phys_score='PHYS', mental_score='MENT', all_score='ALL',
    name='Name', tag='Tag'
}

-------------------------------------------------
-- DF-Style Attribute Descriptors
-- Based on wiki: thresholds are 250/500/750/1000 from species median
-- Using median=1000 as baseline (like humans)
-------------------------------------------------

-- Positive descriptors (value > median + threshold)
-- Negative descriptors (value < median - threshold)
-- Format: {threshold_offset, positive_descriptor, negative_descriptor}

-- Get simple symbol for attribute value (for vague mode)
-- Returns symbol and color
local function get_attr_symbol(value)
    local diff = value - 1000
    if diff >= 750 then return "+++", COLOR_LIGHTGREEN
    elseif diff >= 400 then return "++", COLOR_GREEN
    elseif diff >= 150 then return "+", COLOR_CYAN
    elseif diff <= -750 then return "---", COLOR_LIGHTRED
    elseif diff <= -400 then return "--", COLOR_RED
    elseif diff <= -150 then return "-", COLOR_BROWN
    else return "~", COLOR_GRAY
    end
end

-------------------------------------------------
-- Color Functions
-------------------------------------------------

local function get_attr_color(value)
    if value >= 2000 then return COLOR_LIGHTGREEN
    elseif value >= 1500 then return COLOR_GREEN
    elseif value >= 1200 then return COLOR_YELLOW
    elseif value >= 900 then return COLOR_BROWN
    elseif value >= 600 then return COLOR_LIGHTRED
    else return COLOR_RED
    end
end

local function get_pct_color(pct)
    if pct >= 90 then return COLOR_LIGHTGREEN
    elseif pct >= 70 then return COLOR_GREEN
    elseif pct >= 50 then return COLOR_YELLOW
    elseif pct >= 30 then return COLOR_BROWN
    else return COLOR_LIGHTRED
    end
end

local function get_body_color(val)
    if val >= 110 then return COLOR_LIGHTGREEN
    elseif val >= 105 then return COLOR_GREEN
    elseif val >= 95 then return COLOR_WHITE
    elseif val >= 90 then return COLOR_YELLOW
    else return COLOR_LIGHTRED
    end
end

-------------------------------------------------
-- Cage Functions
-------------------------------------------------

local function is_in_cage(unit)
    for _, bld in ipairs(df.global.world.buildings.all) do
        if bld:getType() == df.building_type.Cage then
            if bld.assigned_units then
                for _, uid in ipairs(bld.assigned_units) do
                    if uid == unit.id then
                        return true, bld
                    end
                end
            end
        end
    end
    if unit.flags1.caged then
        return true, nil
    end
    return false, nil
end

local function find_empty_cages()
    local cages = {}
    for _, bld in ipairs(df.global.world.buildings.all) do
        if bld:getType() == df.building_type.Cage then
            if bld.flags.exists then
                local is_empty = true
                if bld.assigned_units and #bld.assigned_units > 0 then
                    is_empty = false
                end
                if bld.contained_items then
                    for _, it in ipairs(bld.contained_items) do
                        if it.use_mode == 0 then
                            local item = it.item
                            if item:getType() == df.item_type.CAGE then
                                local cage_item = item --as:df.item_cagest
                                if cage_item.general_refs then
                                    for _, ref in ipairs(cage_item.general_refs) do
                                        if df.general_ref_contains_unitst:is_instance(ref) then
                                            is_empty = false
                                            break
                                        end
                                    end
                                end
                            end
                        end
                    end
                end
                if is_empty then
                    table.insert(cages, bld)
                end
            end
        end
    end
    return cages
end

local function assign_to_cage(unit, cage)
    if not cage or not unit then return false end
    if cage.assigned_units then
        cage.assigned_units:insert('#', unit.id)
        return true
    end
    return false
end

local function unassign_from_cage(unit)
    for _, bld in ipairs(df.global.world.buildings.all) do
        if bld:getType() == df.building_type.Cage then
            if bld.assigned_units then
                for i = #bld.assigned_units - 1, 0, -1 do
                    if bld.assigned_units[i] == unit.id then
                        bld.assigned_units:erase(i)
                        return true
                    end
                end
            end
        end
    end
    return false
end

local function unassign_from_zones(unit)
    local dominated_list = false
    
    -- Step 1: Remove unit from all zone assigned_units lists
    for _, bld in ipairs(df.global.world.buildings.all) do
        if bld:getType() == df.building_type.Civzone then
            if bld.assigned_units then
                for i = #bld.assigned_units - 1, 0, -1 do
                    if bld.assigned_units[i] == unit.id then
                        bld.assigned_units:erase(i)
                        dominated_list = true
                    end
                end
            end
        end
    end
    
    -- Step 2: Remove zone refs from unit's general_refs
    if unit.general_refs then
        for i = #unit.general_refs - 1, 0, -1 do
            local ref = unit.general_refs[i]
            if df.general_ref_building_civzone_assignedst:is_instance(ref) then
                unit.general_refs:erase(i)
                dominated_list = true
            end
        end
    end
    
    return dominated_list
end

local function is_assigned_to_zone(unit)
    -- Check unit's general_refs for zone assignment
    if unit.general_refs then
        for _, ref in ipairs(unit.general_refs) do
            if df.general_ref_building_civzone_assignedst:is_instance(ref) then
                return true
            end
        end
    end
    return false
end

-------------------------------------------------
-- Animal Data Functions
-------------------------------------------------

local function is_valid_animal(unit)
    if not dfhack.units.isActive(unit) then return false end
    if dfhack.units.isDead(unit) then return false end
    if not dfhack.units.isAnimal(unit) then return false end
    if not dfhack.units.isTame(unit) then return false end
    if dfhack.units.isHunter(unit) then return false end
    if dfhack.units.isWar(unit) then return false end
    return true
end

local function is_adult(unit)
    if dfhack.units.isAdult then
        return dfhack.units.isAdult(unit)
    end
    if unit.flags1.child or unit.flags1.baby then
        return false
    end
    return true
end

local function is_marked_for_slaughter(unit)
    return unit.flags2.slaughter
end

local function get_parent_ids(unit)
    local mother_id = -1
    local father_id = -1
    
    -- Try different ways to get parent info
    if unit.relationship_ids then
        if unit.relationship_ids.Mother and unit.relationship_ids.Mother ~= -1 then
            mother_id = unit.relationship_ids.Mother
        end
        if unit.relationship_ids.Father and unit.relationship_ids.Father ~= -1 then
            father_id = unit.relationship_ids.Father
        end
    end
    
    return mother_id, father_id
end

local function get_attrs(unit)
    local attrs = {}
    local phys_total = 0
    local mental_total = 0
    
    for _, name in ipairs(PHYS_ATTRS) do
        local id = df.physical_attribute_type[name]
        if id then
            local val = unit.body.physical_attrs[id].value
            attrs[name] = val
            phys_total = phys_total + val
        end
    end
    
    for _, name in ipairs(MENTAL_ATTRS) do
        local id = df.mental_attribute_type[name]
        if id then
            local val = unit.status.current_soul and unit.status.current_soul.mental_attrs[id].value or 0
            attrs[name] = val
            mental_total = mental_total + val
        end
    end
    
    attrs.phys_score = math.floor(phys_total / #PHYS_ATTRS)
    attrs.mental_score = math.floor(mental_total / #MENTAL_ATTRS)
    attrs.all_score = math.floor((phys_total + mental_total) / (#PHYS_ATTRS + #MENTAL_ATTRS))
    return attrs
end

local function get_nickname(unit)
    if unit.name and unit.name.nickname and unit.name.nickname ~= "" then
        return unit.name.nickname
    end
    return nil
end

local function parse_nickname(nickname)
    if not nickname then return nil, nil end
    local tag = nickname:match("%[%w+%]")
    local name = nickname:gsub("%s*%[%w+%]%s*", ""):match("^%s*(.-)%s*$")
    if name == "" then name = nil end
    return name, tag
end

local function make_nickname(name, tag)
    if name and tag then
        return name .. " " .. tag
    elseif name then
        return name
    elseif tag then
        return tag
    else
        return ""
    end
end

-- Get body appearance modifiers (HEIGHT, BROADNESS, LENGTH)
-- These affect butcher yields and are supposedly inheritable
local function get_body_modifiers(unit)
    local mods = {height = 100, broadness = 100, length = 100}
    
    -- Try to access appearance modifiers
    if unit.appearance and unit.appearance.body_modifiers then
        local body_mods = unit.appearance.body_modifiers
        -- The order depends on the creature's raw definition
        -- Typically: HEIGHT, BROADNESS, LENGTH for body
        -- We need to map them based on the creature's BP_APPEARANCE_MODIFIER tokens
        
        -- For now, try to get raw values if they exist
        if #body_mods >= 1 then mods.height = body_mods[0] or 100 end
        if #body_mods >= 2 then mods.broadness = body_mods[1] or 100 end
        if #body_mods >= 3 then mods.length = body_mods[2] or 100 end
    end
    
    -- Calculate combined size modifier (affects butcher yields)
    mods.size_pct = math.floor((mods.height * mods.broadness * mods.length) / 10000)
    
    return mods
end

local function gather_all_animals()
    local animals = {}
    for _, unit in ipairs(df.global.world.units.active) do
        if is_valid_animal(unit) then
            local race_raw = df.creature_raw.find(unit.race)
            local race_name = race_raw and race_raw.creature_id or "UNKNOWN"
            local sex = unit.sex == 1 and "M" or "F"
            local attrs = get_attrs(unit)
            local nickname = get_nickname(unit)
            local name, tag = parse_nickname(nickname)
            local caged, _ = is_in_cage(unit)
            local mother_id, father_id = get_parent_ids(unit)
            local body_mods = get_body_modifiers(unit)
            
            table.insert(animals, {
                unit = unit,
                id = unit.id,
                race = race_name,
                sex = sex,
                attrs = attrs,
                gelded = unit.flags3.gelded,
                nickname = nickname,
                name = name,
                tag = tag,
                marked = false,
                caged = caged,
                adult = is_adult(unit),
                slaughter = is_marked_for_slaughter(unit),
                mother_id = mother_id,
                father_id = father_id,
                phys_pct = 0,
                ment_pct = 0,
                all_pct = 0,
                herd_rank = 0,
                body_height = body_mods.height,
                body_broadness = body_mods.broadness,
                body_length = body_mods.length,
                body_size_pct = body_mods.size_pct,
            })
        end
    end
    return animals
end

local function get_species_list(animals)
    local species = {}
    local seen = {}
    for _, a in ipairs(animals) do
        if not seen[a.race] then
            seen[a.race] = true
            local count = 0
            for _, b in ipairs(animals) do
                if b.race == a.race then count = count + 1 end
            end
            table.insert(species, {name = a.race, count = count})
        end
    end
    table.sort(species, function(a,b) return a.name < b.name end)
    return species
end

local function calculate_percentiles(animals)
    if #animals <= 1 then
        for _, a in ipairs(animals) do
            a.phys_pct = 100
            a.ment_pct = 100
            a.all_pct = 100
            a.herd_rank = 1
        end
        return
    end
    
    -- Calculate percentiles for each score type
    local function calc_pct(list, getter, setter)
        local sorted = {}
        for i, a in ipairs(list) do
            table.insert(sorted, {idx=i, val=getter(a)})
        end
        table.sort(sorted, function(a,b) return a.val < b.val end)
        for rank, entry in ipairs(sorted) do
            local pct = math.floor((rank - 1) / (#sorted - 1) * 100)
            setter(list[entry.idx], pct)
        end
    end
    
    calc_pct(animals, function(a) return a.attrs.phys_score end, function(a, v) a.phys_pct = v end)
    calc_pct(animals, function(a) return a.attrs.mental_score end, function(a, v) a.ment_pct = v end)
    calc_pct(animals, function(a) return a.attrs.all_score end, function(a, v) a.all_pct = v end)
    
    -- Calculate herd rank (by overall score, 1 = best)
    local sorted_by_all = {}
    for i, a in ipairs(animals) do
        table.insert(sorted_by_all, {idx=i, val=a.attrs.all_score})
    end
    table.sort(sorted_by_all, function(a,b) return a.val > b.val end)
    for rank, entry in ipairs(sorted_by_all) do
        animals[entry.idx].herd_rank = rank
    end
end

local function calculate_generations(animals)
    -- Build ID lookup table
    local by_id = {}
    for _, a in ipairs(animals) do
        by_id[a.id] = a
    end
    
    -- Recursive generation calculator with memoization
    local function get_gen(animal)
        if animal.generation then return animal.generation end
        
        local mother = by_id[animal.mother_id]
        local father = by_id[animal.father_id]
        
        -- No parents in current herd = founder (F0)
        if not mother and not father then
            animal.generation = 0
            return 0
        end
        
        -- Generation = max(parent generations) + 1
        local mother_gen = mother and get_gen(mother) or -1
        local father_gen = father and get_gen(father) or -1
        
        animal.generation = math.max(mother_gen, father_gen) + 1
        return animal.generation
    end
    
    -- Calculate for all animals
    for _, a in ipairs(animals) do
        get_gen(a)
    end
end

-------------------------------------------------
-- Main UI
-------------------------------------------------

AnimalBreeder = defclass(AnimalBreeder, gui.ZScreen)
AnimalBreeder.ATTRS{
    focus_path = 'animal-breeder',
    init_args = DEFAULT_NIL,
}

function AnimalBreeder:init()
    local args = self.init_args or {}
    
    self.all_animals = gather_all_animals()
    self.species_list = get_species_list(self.all_animals)
    self.current_species = animal_breeder_last_species
    self.filtered_animals = {}
    self.sort_attr = 'all_score'
    self.sort_desc = true
    self.last_click_idx = nil
    
    -- Determine mode: --detailed flag or default vague
    self.vague_mode = not args.detailed
    
    -- Filters
    self.show_males = true
    self.show_females = true
    self.show_adults = true
    self.show_juveniles = true
    self.show_gelded = true
    self.show_caged = true
    self.filter_attr = "NONE"
    self.filter_min = 0
    self.name_filter = ""
    
    local attr_options = {{label="NONE", value="NONE"}}
    for _, a in ipairs(ALL_ATTRS) do
        table.insert(attr_options, {label=ATTR_SHORT[a], value=a})
    end
    table.insert(attr_options, {label="PHYS", value="phys_score"})
    table.insert(attr_options, {label="MENT", value="mental_score"})
    table.insert(attr_options, {label="ALL", value="all_score"})
    
    self:addviews{
        widgets.Window{
            frame = {w=170, h=45},
            frame_title = "Animal Breeder - Attribute Manager",
            resizable = true,
            subviews = {
                -- Row 1: Species selector
                widgets.Panel{
                    frame = {t=0, l=0, r=0, h=1},
                    subviews = {
                        widgets.Label{frame={t=0,l=0}, text="Species:"},
                        widgets.Label{
                            view_id = 'species_label',
                            frame = {t=0, l=9, w=25},
                            text = "None selected",
                            text_pen = COLOR_YELLOW,
                            on_click = function() self:show_species_picker() end,
                        },
                        widgets.HotkeyLabel{
                            frame = {t=0, l=35},
                            label = "Pick",
                            key = "CUSTOM_P",
                            on_activate = function() self:show_species_picker() end,
                        },
                        widgets.HotkeyLabel{
                            frame = {t=0, l=48},
                            label = "Refresh",
                            key = "CUSTOM_SHIFT_R",
                            on_activate = function() self:full_refresh() end,
                        },
                        widgets.HotkeyLabel{
                            frame = {t=0, l=63},
                            label = "Filter",
                            key = "CUSTOM_F",
                            on_activate = function() self:show_text_filter() end,
                        },
                        widgets.Label{
                            view_id = 'filter_label',
                            frame = {t=0, l=76},
                            text = "",
                            text_pen = COLOR_CYAN,
                        },
                        -- Mode indicator (fixed position)
                        widgets.Label{
                            view_id = 'mode_label',
                            frame = {t=0, r=0, w=16},
                            text = "Mode: Vague",
                            text_pen = COLOR_GREEN,
                        },
                    },
                },
                -- Row 2: Filters
                widgets.Panel{
                    frame = {t=2, l=0, r=0, h=1},
                    subviews = {
                        widgets.ToggleHotkeyLabel{
                            view_id = 'tog_male',
                            frame = {t=0, l=0},
                            label = "Male",
                            initial_option = true,
                            on_change = function(val) self.show_males = val; self:refresh() end,
                        },
                        widgets.ToggleHotkeyLabel{
                            view_id = 'tog_female',
                            frame = {t=0, l=11},
                            label = "Fem",
                            initial_option = true,
                            on_change = function(val) self.show_females = val; self:refresh() end,
                        },
                        widgets.ToggleHotkeyLabel{
                            view_id = 'tog_adult',
                            frame = {t=0, l=21},
                            label = "Adult",
                            initial_option = true,
                            on_change = function(val) self.show_adults = val; self:refresh() end,
                        },
                        widgets.ToggleHotkeyLabel{
                            view_id = 'tog_juv',
                            frame = {t=0, l=33},
                            label = "Juv",
                            initial_option = true,
                            on_change = function(val) self.show_juveniles = val; self:refresh() end,
                        },
                        widgets.ToggleHotkeyLabel{
                            view_id = 'tog_gelded',
                            frame = {t=0, l=43},
                            label = "Geld",
                            initial_option = true,
                            on_change = function(val) self.show_gelded = val; self:refresh() end,
                        },
                        widgets.ToggleHotkeyLabel{
                            view_id = 'tog_caged',
                            frame = {t=0, l=54},
                            label = "Cage",
                            initial_option = true,
                            on_change = function(val) self.show_caged = val; self:refresh() end,
                        },
                        widgets.Label{frame={t=0,l=66}, text="Attr:"},
                        widgets.CycleHotkeyLabel{
                            view_id = 'filter_attr',
                            frame = {t=0, l=72},
                            label = "",
                            options = attr_options,
                            on_change = function(val) self.filter_attr = val; self:refresh() end,
                        },
                        widgets.Label{frame={t=0,l=86}, text="Min:"},
                        widgets.CycleHotkeyLabel{
                            view_id = 'filter_min',
                            frame = {t=0, l=91},
                            label = "",
                            options = {
                                {label="0", value=0}, {label="500", value=500}, {label="750", value=750},
                                {label="1000", value=1000}, {label="1250", value=1250}, {label="1500", value=1500},
                                {label="1750", value=1750}, {label="2000", value=2000},
                            },
                            on_change = function(val) self.filter_min = val; self:refresh() end,
                        },
                        widgets.Label{frame={t=0,l=105}, text="Sort:"},
                        widgets.CycleHotkeyLabel{
                            view_id = 'sort_cycle',
                            frame = {t=0, l=111},
                            label = "",
                            options = {
                                {label="Rank", value="all_score"},
                                {label="Gen", value="generation"},
                                {label="STR", value="STRENGTH"},
                                {label="AGI", value="AGILITY"},
                                {label="TGH", value="TOUGHNESS"},
                                {label="END", value="ENDURANCE"},
                                {label="REC", value="RECUPERATION"},
                                {label="DIS", value="DISEASE_RESISTANCE"},
                                {label="WIL", value="WILLPOWER"},
                                {label="FOC", value="FOCUS"},
                                {label="SPA", value="SPATIAL_SENSE"},
                                {label="KIN", value="KINESTHETIC_SENSE"},
                                {label="H%", value="body_height"},
                                {label="B%", value="body_broadness"},
                                {label="L%", value="body_length"},
                                {label="Size", value="body_size_pct"},
                                {label="Caged", value="caged"},
                                {label="Zoned", value="zoned"},
                                {label="Gelded", value="gelded"},
                                {label="Butch", value="slaughter"},
                            },
                            on_change = function(val) self:set_sort(val) end,
                        },
                        widgets.HotkeyLabel{
                            frame = {t=0, l=130},
                            label = "Export",
                            key = "CUSTOM_E",
                            on_activate = function() self:do_export() end,
                        },
                    },
                },
                -- Row 3: Column headers (dynamic based on mode)
                widgets.Panel{
                    view_id = 'header_panel',
                    frame = {t=4, l=0, r=0, h=1},
                    subviews = {},  -- Will be populated by update_headers()
                },
                -- List
                widgets.List{
                    view_id = 'list',
                    frame = {t=6, l=0, r=0, b=6},
                    on_select = self:callback('on_select'),
                    on_submit = self:callback('on_submit'),
                    row_height = 1,
                },
                -- Status line
                widgets.Label{
                    view_id = 'status',
                    frame = {b=5, l=0},
                    text = "",
                },
                -- Action buttons
                widgets.Panel{
                    frame = {b=2, l=0, r=0, h=2},
                    subviews = {
                        widgets.HotkeyLabel{frame={t=0,l=0}, label="Mark", key="CUSTOM_M", on_activate=function() self:do_toggle_mark() end},
                        widgets.HotkeyLabel{frame={t=0,l=12}, label="MarkAll", key="CUSTOM_A", on_activate=function() self:do_mark_all() end},
                        widgets.HotkeyLabel{frame={t=0,l=26}, label="Unmark", key="CUSTOM_U", on_activate=function() self:do_unmark_all() end},
                        widgets.Label{frame={t=0,l=42}, text="[Enter=mark, Shift+Click=range]", text_pen=COLOR_GRAY},
                        widgets.HotkeyLabel{frame={t=1,l=0}, label="Name", key="CUSTOM_N", on_activate=function() self:do_name() end},
                        widgets.HotkeyLabel{frame={t=1,l=12}, label="Tag", key="CUSTOM_T", on_activate=function() self:do_tag() end},
                        widgets.HotkeyLabel{frame={t=1,l=22}, label="Geld", key="CUSTOM_G", on_activate=function() self:do_geld() end},
                        widgets.HotkeyLabel{frame={t=1,l=33}, label="Cage", key="CUSTOM_X", on_activate=function() self:do_cage() end},
                        widgets.HotkeyLabel{frame={t=1,l=44}, label="Uncage", key="CUSTOM_R", on_activate=function() self:do_uncage() end},
                        widgets.HotkeyLabel{frame={t=1,l=57}, label="Butcher", key="CUSTOM_B", on_activate=function() self:do_butcher() end},
                        widgets.HotkeyLabel{frame={t=1,l=71}, label="Unbutch", key="CUSTOM_V", on_activate=function() self:do_unbutcher() end},
                        widgets.HotkeyLabel{frame={t=1,l=85}, label="Clear", key="CUSTOM_C", on_activate=function() self:do_clear_name() end},
                    },
                },
                -- Close button
                widgets.HotkeyLabel{frame={b=0,l=0}, label="Close", key="LEAVESCREEN", on_activate=function() self:dismiss() end},
            }
        }
    }
    
    self:update_headers()
    self:update_species()
end

function AnimalBreeder:update_headers()
    local header_panel = self.subviews.header_panel
    header_panel.subviews = {}
    
    if self.vague_mode then
        -- Vague mode: symbol-based attribute columns (sortable)
        header_panel:addviews{
            widgets.Label{frame={t=0,l=0,w=2}, text="  ", text_pen=COLOR_LIGHTBLUE},
            widgets.Label{frame={t=0,l=2,w=6}, text="ID", text_pen=COLOR_LIGHTBLUE, on_click=function() self:set_sort("id") end},
            widgets.Label{frame={t=0,l=9,w=5}, text="Sex", text_pen=COLOR_LIGHTBLUE, on_click=function() self:set_sort("sex") end},
            widgets.Label{frame={t=0,l=14,w=3}, text="Gen", text_pen=COLOR_LIGHTBLUE, on_click=function() self:set_sort("generation") end},
            widgets.Label{frame={t=0,l=18,w=8}, text="Status", text_pen=COLOR_LIGHTBLUE, on_click=function() self:set_sort("caged") end},
            widgets.Label{frame={t=0,l=27,w=9}, text="Name", text_pen=COLOR_LIGHTBLUE, on_click=function() self:set_sort("name") end},
            widgets.Label{frame={t=0,l=37,w=8}, text="Tag", text_pen=COLOR_LIGHTBLUE, on_click=function() self:set_sort("tag") end},
            -- Physical attrs (4 chars each for symbols)
            widgets.Label{frame={t=0,l=46,w=4}, text="STR", text_pen=COLOR_LIGHTCYAN, on_click=function() self:set_sort("STRENGTH") end},
            widgets.Label{frame={t=0,l=50,w=4}, text="AGI", text_pen=COLOR_LIGHTCYAN, on_click=function() self:set_sort("AGILITY") end},
            widgets.Label{frame={t=0,l=54,w=4}, text="TGH", text_pen=COLOR_LIGHTCYAN, on_click=function() self:set_sort("TOUGHNESS") end},
            widgets.Label{frame={t=0,l=58,w=4}, text="END", text_pen=COLOR_LIGHTCYAN, on_click=function() self:set_sort("ENDURANCE") end},
            widgets.Label{frame={t=0,l=62,w=4}, text="REC", text_pen=COLOR_LIGHTCYAN, on_click=function() self:set_sort("RECUPERATION") end},
            widgets.Label{frame={t=0,l=66,w=4}, text="DIS", text_pen=COLOR_LIGHTCYAN, on_click=function() self:set_sort("DISEASE_RESISTANCE") end},
            -- Mental attrs
            widgets.Label{frame={t=0,l=70,w=4}, text="WIL", text_pen=COLOR_LIGHTMAGENTA, on_click=function() self:set_sort("WILLPOWER") end},
            widgets.Label{frame={t=0,l=74,w=4}, text="FOC", text_pen=COLOR_LIGHTMAGENTA, on_click=function() self:set_sort("FOCUS") end},
            widgets.Label{frame={t=0,l=78,w=4}, text="SPA", text_pen=COLOR_LIGHTMAGENTA, on_click=function() self:set_sort("SPATIAL_SENSE") end},
            widgets.Label{frame={t=0,l=82,w=4}, text="KIN", text_pen=COLOR_LIGHTMAGENTA, on_click=function() self:set_sort("KINESTHETIC_SENSE") end},
            -- Body modifiers (numbers)
            widgets.Label{frame={t=0,l=86,w=4}, text="H%", text_pen=COLOR_YELLOW, on_click=function() self:set_sort("body_height") end},
            widgets.Label{frame={t=0,l=90,w=4}, text="B%", text_pen=COLOR_YELLOW, on_click=function() self:set_sort("body_broadness") end},
            widgets.Label{frame={t=0,l=94,w=4}, text="L%", text_pen=COLOR_YELLOW, on_click=function() self:set_sort("body_length") end},
        }
    else
        -- Detailed mode: all numeric columns
        -- Column positions match row format strings exactly
        header_panel:addviews{
            widgets.Label{frame={t=0,l=0,w=2}, text="  ", text_pen=COLOR_LIGHTBLUE},
            widgets.Label{frame={t=0,l=2,w=6}, text="ID", text_pen=COLOR_LIGHTBLUE, on_click=function() self:set_sort("id") end},
            widgets.Label{frame={t=0,l=9,w=5}, text="Sex", text_pen=COLOR_LIGHTBLUE, on_click=function() self:set_sort("sex") end},
            widgets.Label{frame={t=0,l=15,w=3}, text="Gen", text_pen=COLOR_LIGHTBLUE, on_click=function() self:set_sort("generation") end},
            widgets.Label{frame={t=0,l=19,w=9}, text="Status", text_pen=COLOR_LIGHTBLUE, on_click=function() self:set_sort("caged") end},
            widgets.Label{frame={t=0,l=28,w=10}, text="Name", text_pen=COLOR_LIGHTBLUE, on_click=function() self:set_sort("name") end},
            widgets.Label{frame={t=0,l=38,w=10}, text="Tag", text_pen=COLOR_LIGHTBLUE, on_click=function() self:set_sort("tag") end},
            -- Physical attrs (6 chars each: %5d + space)
            widgets.Label{frame={t=0,l=48,w=6}, text="STR", text_pen=COLOR_LIGHTCYAN, on_click=function() self:set_sort("STRENGTH") end},
            widgets.Label{frame={t=0,l=54,w=6}, text="AGI", text_pen=COLOR_LIGHTCYAN, on_click=function() self:set_sort("AGILITY") end},
            widgets.Label{frame={t=0,l=60,w=6}, text="TGH", text_pen=COLOR_LIGHTCYAN, on_click=function() self:set_sort("TOUGHNESS") end},
            widgets.Label{frame={t=0,l=66,w=6}, text="END", text_pen=COLOR_LIGHTCYAN, on_click=function() self:set_sort("ENDURANCE") end},
            widgets.Label{frame={t=0,l=72,w=6}, text="REC", text_pen=COLOR_LIGHTCYAN, on_click=function() self:set_sort("RECUPERATION") end},
            widgets.Label{frame={t=0,l=78,w=6}, text="DIS", text_pen=COLOR_LIGHTCYAN, on_click=function() self:set_sort("DISEASE_RESISTANCE") end},
            -- Mental attrs
            widgets.Label{frame={t=0,l=84,w=6}, text="WIL", text_pen=COLOR_LIGHTMAGENTA, on_click=function() self:set_sort("WILLPOWER") end},
            widgets.Label{frame={t=0,l=90,w=6}, text="FOC", text_pen=COLOR_LIGHTMAGENTA, on_click=function() self:set_sort("FOCUS") end},
            widgets.Label{frame={t=0,l=96,w=6}, text="SPA", text_pen=COLOR_LIGHTMAGENTA, on_click=function() self:set_sort("SPATIAL_SENSE") end},
            widgets.Label{frame={t=0,l=102,w=6}, text="KIN", text_pen=COLOR_LIGHTMAGENTA, on_click=function() self:set_sort("KINESTHETIC_SENSE") end},
            -- Scores (5 chars each: %4d + space)
            widgets.Label{frame={t=0,l=108,w=5}, text="PHYS", text_pen=COLOR_GREEN, on_click=function() self:set_sort("phys_score") end},
            widgets.Label{frame={t=0,l=113,w=5}, text="MENT", text_pen=COLOR_YELLOW, on_click=function() self:set_sort("mental_score") end},
            widgets.Label{frame={t=0,l=118,w=5}, text="ALL%", text_pen=COLOR_WHITE, on_click=function() self:set_sort("all_score") end},
            -- Body modifiers (5 chars each: %4d + space)
            widgets.Label{frame={t=0,l=123,w=5}, text="H%", text_pen=COLOR_LIGHTBLUE, on_click=function() self:set_sort("body_height") end},
            widgets.Label{frame={t=0,l=128,w=5}, text="B%", text_pen=COLOR_LIGHTBLUE, on_click=function() self:set_sort("body_broadness") end},
            widgets.Label{frame={t=0,l=133,w=5}, text="L%", text_pen=COLOR_LIGHTBLUE, on_click=function() self:set_sort("body_length") end},
            widgets.Label{frame={t=0,l=138,w=4}, text="SIZE", text_pen=COLOR_WHITE, on_click=function() self:set_sort("body_size_pct") end},
        }
    end
    
    -- Update mode label
    if self.subviews.mode_label then
        if self.vague_mode then
            self.subviews.mode_label:setText("Mode: Vague")
            self.subviews.mode_label.text_pen = COLOR_GREEN
        else
            self.subviews.mode_label:setText("Mode: Detailed")
            self.subviews.mode_label.text_pen = COLOR_CYAN
        end
    end
end

function AnimalBreeder:show_species_picker()
    local choices = {}
    for _, sp in ipairs(self.species_list) do
        table.insert(choices, {
            text = string.format("%-25s (%d)", sp.name, sp.count),
            species = sp.name,
        })
    end
    
    dlg.showListPrompt(
        "Select Species",
        "Type to filter, Enter to select:",
        COLOR_WHITE,
        choices,
        function(idx, choice)
            if choice then
                self.current_species = choice.species
                animal_breeder_last_species = choice.species
                self:update_species()
            end
        end,
        nil, nil, true
    )
end

function AnimalBreeder:show_text_filter()
    dlg.showInputPrompt(
        "Filter by Name/Tag",
        "Enter text to filter (leave empty to clear):",
        COLOR_WHITE,
        self.name_filter,
        function(text)
            self.name_filter = text or ""
            self:refresh()
        end
    )
end

function AnimalBreeder:set_sort(attr)
    if self.sort_attr == attr then
        self.sort_desc = not self.sort_desc
    else
        self.sort_attr = attr
        if attr == "name" or attr == "tag" or attr == "sex" then
            self.sort_desc = false
        else
            self.sort_desc = true
        end
    end
    self:refresh()
end

function AnimalBreeder:update_species()
    self.filtered_animals = {}
    if not self.current_species then return end
    
    for _, a in ipairs(self.all_animals) do
        if a.race == self.current_species then
            a.marked = false
            a.caged = is_in_cage(a.unit)
            a.adult = is_adult(a.unit)
            a.slaughter = is_marked_for_slaughter(a.unit)
            a.zoned = is_assigned_to_zone(a.unit)
            table.insert(self.filtered_animals, a)
        end
    end
    
    calculate_percentiles(self.filtered_animals)
    calculate_generations(self.filtered_animals)
    self.last_click_idx = nil
    self:refresh()
end

function AnimalBreeder:count_marked()
    local count = 0
    for _, a in ipairs(self.filtered_animals) do
        if a.marked then count = count + 1 end
    end
    return count
end

function AnimalBreeder:get_display_animals()
    local result = {}
    local name_filter_lower = self.name_filter:lower()
    
    for _, a in ipairs(self.filtered_animals) do
        a.gelded = a.unit.flags3.gelded
        a.nickname = get_nickname(a.unit)
        a.name, a.tag = parse_nickname(a.nickname)
        a.caged = is_in_cage(a.unit)
        a.adult = is_adult(a.unit)
        a.slaughter = is_marked_for_slaughter(a.unit)
        a.zoned = is_assigned_to_zone(a.unit)
        
        local dominated_list = true
        
        if a.sex == "M" and not a.gelded and not self.show_males then dominated_list = false end
        if a.sex == "F" and not self.show_females then dominated_list = false end
        if a.gelded and not self.show_gelded then dominated_list = false end
        if a.caged and not self.show_caged then dominated_list = false end
        if a.adult and not self.show_adults then dominated_list = false end
        if not a.adult and not self.show_juveniles then dominated_list = false end
        
        if self.filter_attr ~= "NONE" and self.filter_min > 0 then
            local val
            if self.filter_attr == "phys_score" then
                val = a.attrs.phys_score
            elseif self.filter_attr == "mental_score" then
                val = a.attrs.mental_score
            elseif self.filter_attr == "all_score" then
                val = a.attrs.all_score
            else
                val = a.attrs[self.filter_attr] or 0
            end
            if val < self.filter_min then dominated_list = false end
        end
        
        if name_filter_lower ~= "" then
            local name_lower = (a.name or ""):lower()
            local tag_lower = (a.tag or ""):lower()
            if not name_lower:find(name_filter_lower, 1, true) and 
               not tag_lower:find(name_filter_lower, 1, true) then
                dominated_list = false
            end
        end
        
        if dominated_list then
            table.insert(result, a)
        end
    end
    
    local sort_key = self.sort_attr
    local desc = self.sort_desc
    table.sort(result, function(a, b)
        local va, vb
        if sort_key == "id" then
            va, vb = a.id, b.id
        elseif sort_key == "sex" then
            va, vb = a.sex, b.sex
        elseif sort_key == "name" then
            va, vb = (a.name or ""), (b.name or "")
        elseif sort_key == "tag" then
            va, vb = (a.tag or ""), (b.tag or "")
        elseif sort_key == "phys_score" then
            va, vb = a.attrs.phys_score, b.attrs.phys_score
        elseif sort_key == "mental_score" then
            va, vb = a.attrs.mental_score, b.attrs.mental_score
        elseif sort_key == "all_score" then
            va, vb = a.attrs.all_score, b.attrs.all_score
        elseif sort_key == "body_height" then
            va, vb = a.body_height or 100, b.body_height or 100
        elseif sort_key == "body_broadness" then
            va, vb = a.body_broadness or 100, b.body_broadness or 100
        elseif sort_key == "body_length" then
            va, vb = a.body_length or 100, b.body_length or 100
        elseif sort_key == "body_size_pct" then
            va, vb = a.body_size_pct or 100, b.body_size_pct or 100
        elseif sort_key == "caged" then
            va, vb = a.caged and 1 or 0, b.caged and 1 or 0
        elseif sort_key == "zoned" then
            va, vb = a.zoned and 1 or 0, b.zoned and 1 or 0
        elseif sort_key == "gelded" then
            va, vb = a.gelded and 1 or 0, b.gelded and 1 or 0
        elseif sort_key == "slaughter" then
            va, vb = a.slaughter and 1 or 0, b.slaughter and 1 or 0
        elseif sort_key == "generation" then
            va, vb = a.generation or 0, b.generation or 0
        else
            va = a.attrs[sort_key] or 0
            vb = b.attrs[sort_key] or 0
        end
        if desc then
            return va > vb
        else
            return va < vb
        end
    end)
    
    return result
end

function AnimalBreeder:build_vague_row(a)
    local mark_char = a.marked and "*" or " "
    local sex_age = a.sex .. (a.adult and "-A" or "-J")
    
    -- Generation (separate column)
    local gen = a.generation or 0
    local gen_str = "F" .. gen
    
    -- Status flags (without generation)
    local status_parts = {}
    if a.gelded then table.insert(status_parts, "Gld") end
    if a.caged then table.insert(status_parts, "Cge") end
    if a.zoned then table.insert(status_parts, "Zn") end
    if a.slaughter then table.insert(status_parts, "But") end
    local status_str = #status_parts > 0 and table.concat(status_parts, " ") or "-"
    
    local name_display = a.name or "-"
    if #name_display > 8 then name_display = name_display:sub(1,7) .. "." end
    
    local tag_display = a.tag or "-"
    if #tag_display > 7 then tag_display = tag_display:sub(1,6) .. "." end
    
    -- Colors
    local sex_color = a.sex == "F" and COLOR_LIGHTMAGENTA or COLOR_LIGHTCYAN
    if not a.adult then sex_color = COLOR_BROWN end
    if a.slaughter then sex_color = COLOR_LIGHTRED end
    
    local gen_color = COLOR_CYAN
    if gen >= 3 then gen_color = COLOR_LIGHTGREEN
    elseif gen >= 2 then gen_color = COLOR_GREEN
    elseif gen >= 1 then gen_color = COLOR_YELLOW
    end
    
    local status_color = COLOR_GRAY
    if a.slaughter then status_color = COLOR_RED
    elseif a.caged then status_color = COLOR_YELLOW
    elseif a.gelded then status_color = COLOR_BROWN
    end
    
    -- Build line with base info
    local line = {
        {text=mark_char .. " ", pen=a.marked and COLOR_YELLOW or COLOR_WHITE},
        {text=string.format("%-6d ", a.id), pen=COLOR_WHITE},
        {text=string.format("%-4s ", sex_age), pen=sex_color},
        {text=string.format("%-3s ", gen_str), pen=gen_color},
        {text=string.format("%-8s ", status_str), pen=status_color},
        {text=string.format("%-9s ", name_display), pen=COLOR_WHITE},
        {text=string.format("%-8s ", tag_display), pen=COLOR_BROWN},
    }
    
    -- Add attribute symbols (physical)
    local str_sym, str_col = get_attr_symbol(a.attrs.STRENGTH or 1000)
    local agi_sym, agi_col = get_attr_symbol(a.attrs.AGILITY or 1000)
    local tgh_sym, tgh_col = get_attr_symbol(a.attrs.TOUGHNESS or 1000)
    local end_sym, end_col = get_attr_symbol(a.attrs.ENDURANCE or 1000)
    local rec_sym, rec_col = get_attr_symbol(a.attrs.RECUPERATION or 1000)
    local dis_sym, dis_col = get_attr_symbol(a.attrs.DISEASE_RESISTANCE or 1000)
    
    table.insert(line, {text=string.format("%-4s", str_sym), pen=str_col})
    table.insert(line, {text=string.format("%-4s", agi_sym), pen=agi_col})
    table.insert(line, {text=string.format("%-4s", tgh_sym), pen=tgh_col})
    table.insert(line, {text=string.format("%-4s", end_sym), pen=end_col})
    table.insert(line, {text=string.format("%-4s", rec_sym), pen=rec_col})
    table.insert(line, {text=string.format("%-4s", dis_sym), pen=dis_col})
    
    -- Add attribute symbols (mental)
    local wil_sym, wil_col = get_attr_symbol(a.attrs.WILLPOWER or 1000)
    local foc_sym, foc_col = get_attr_symbol(a.attrs.FOCUS or 1000)
    local spa_sym, spa_col = get_attr_symbol(a.attrs.SPATIAL_SENSE or 1000)
    local kin_sym, kin_col = get_attr_symbol(a.attrs.KINESTHETIC_SENSE or 1000)
    
    table.insert(line, {text=string.format("%-4s", wil_sym), pen=wil_col})
    table.insert(line, {text=string.format("%-4s", foc_sym), pen=foc_col})
    table.insert(line, {text=string.format("%-4s", spa_sym), pen=spa_col})
    table.insert(line, {text=string.format("%-4s", kin_sym), pen=kin_col})
    
    -- Add body size as numbers (these actually inherit!)
    local h = a.body_height or 100
    local b = a.body_broadness or 100
    local l = a.body_length or 100
    
    table.insert(line, {text=string.format("%3d ", h), pen=get_body_color(h)})
    table.insert(line, {text=string.format("%3d ", b), pen=get_body_color(b)})
    table.insert(line, {text=string.format("%3d ", l), pen=get_body_color(l)})
    
    return line
end

function AnimalBreeder:build_detailed_row(a)
    local mark_char = a.marked and "*" or " "
    local sex_age = a.sex .. (a.adult and "-A" or "-J")
    
    -- Generation (separate column)
    local gen = a.generation or 0
    local gen_str = "F" .. gen
    
    -- Status flags (without generation)
    local status_parts = {}
    if a.gelded then table.insert(status_parts, "Gld") end
    if a.caged then table.insert(status_parts, "Cge") end
    if a.zoned then table.insert(status_parts, "Zn") end
    if a.slaughter then table.insert(status_parts, "But") end
    local status_str = #status_parts > 0 and table.concat(status_parts, " ") or "-"
    
    local name_display = a.name or "-"
    if #name_display > 9 then name_display = name_display:sub(1,8) .. "." end
    
    local tag_display = a.tag or "-"
    if #tag_display > 8 then tag_display = tag_display:sub(1,7) .. "." end
    
    local sex_color = a.sex == "F" and COLOR_LIGHTMAGENTA or COLOR_LIGHTCYAN
    if not a.adult then sex_color = COLOR_BROWN end
    if a.slaughter then sex_color = COLOR_LIGHTRED end
    
    local gen_color = COLOR_CYAN
    if gen >= 3 then gen_color = COLOR_LIGHTGREEN
    elseif gen >= 2 then gen_color = COLOR_GREEN
    elseif gen >= 1 then gen_color = COLOR_YELLOW
    end
    
    local status_color = COLOR_GRAY
    if a.slaughter then status_color = COLOR_RED
    elseif a.caged then status_color = COLOR_YELLOW
    elseif a.gelded then status_color = COLOR_BROWN
    end
    
    local line = {
        {text=mark_char .. " ", pen=a.marked and COLOR_YELLOW or COLOR_WHITE},
        {text=string.format("%-6d ", a.id), pen=COLOR_WHITE},
        {text=string.format("%-5s", sex_age), pen=sex_color},
        {text=string.format("%-3s ", gen_str), pen=gen_color},
        {text=string.format("%-8s ", status_str), pen=status_color},
        {text=string.format("%-10s", name_display), pen=COLOR_WHITE},
        {text=string.format("%-9s ", tag_display), pen=COLOR_BROWN},
        -- Physical attrs with colors
        {text=string.format("%5d ", a.attrs.STRENGTH or 0), pen=get_attr_color(a.attrs.STRENGTH or 0)},
        {text=string.format("%5d ", a.attrs.AGILITY or 0), pen=get_attr_color(a.attrs.AGILITY or 0)},
        {text=string.format("%5d ", a.attrs.TOUGHNESS or 0), pen=get_attr_color(a.attrs.TOUGHNESS or 0)},
        {text=string.format("%5d ", a.attrs.ENDURANCE or 0), pen=get_attr_color(a.attrs.ENDURANCE or 0)},
        {text=string.format("%5d ", a.attrs.RECUPERATION or 0), pen=get_attr_color(a.attrs.RECUPERATION or 0)},
        {text=string.format("%5d ", a.attrs.DISEASE_RESISTANCE or 0), pen=get_attr_color(a.attrs.DISEASE_RESISTANCE or 0)},
        -- Mental attrs with colors
        {text=string.format("%5d ", a.attrs.WILLPOWER or 0), pen=get_attr_color(a.attrs.WILLPOWER or 0)},
        {text=string.format("%5d ", a.attrs.FOCUS or 0), pen=get_attr_color(a.attrs.FOCUS or 0)},
        {text=string.format("%5d ", a.attrs.SPATIAL_SENSE or 0), pen=get_attr_color(a.attrs.SPATIAL_SENSE or 0)},
        {text=string.format("%5d ", a.attrs.KINESTHETIC_SENSE or 0), pen=get_attr_color(a.attrs.KINESTHETIC_SENSE or 0)},
        -- Scores (condensed)
        {text=string.format("%4d ", a.attrs.phys_score), pen=get_attr_color(a.attrs.phys_score)},
        {text=string.format("%4d ", a.attrs.mental_score), pen=get_attr_color(a.attrs.mental_score)},
        {text=string.format("%3d%% ", a.all_pct), pen=get_pct_color(a.all_pct)},
        -- Body modifiers
        {text=string.format("%4d ", a.body_height or 100), pen=get_body_color(a.body_height or 100)},
        {text=string.format("%4d ", a.body_broadness or 100), pen=get_body_color(a.body_broadness or 100)},
        {text=string.format("%4d ", a.body_length or 100), pen=get_body_color(a.body_length or 100)},
        {text=string.format("%4d", a.body_size_pct or 100), pen=get_body_color(a.body_size_pct or 100)},
    }
    
    return line
end

function AnimalBreeder:refresh()
    local display = self:get_display_animals()
    local choices = {}
    
    for i, a in ipairs(display) do
        local line
        if self.vague_mode then
            line = self:build_vague_row(a)
        else
            line = self:build_detailed_row(a)
        end
        
        table.insert(choices, {
            text = line,
            animal = a,
            idx = i,
        })
    end
    
    self.subviews.list:setChoices(choices)
    
    -- Update species label
    if self.current_species then
        self.subviews.species_label:setText(self.current_species)
    else
        self.subviews.species_label:setText("None selected")
    end
    
    -- Update filter label
    if self.name_filter ~= "" then
        self.subviews.filter_label:setText("\"" .. self.name_filter .. "\"")
    else
        self.subviews.filter_label:setText("")
    end
    
    -- Update status
    local marked = self:count_marked()
    local status = string.format("Total: %d | Shown: %d | Marked: %d", 
        #self.filtered_animals, #display, marked)
    self.subviews.status:setText(status)
end

function AnimalBreeder:full_refresh()
    self.all_animals = gather_all_animals()
    self.species_list = get_species_list(self.all_animals)
    self:update_species()
end

function AnimalBreeder:on_select(idx, choice)
    -- Selection tracking for shift-click
end

function AnimalBreeder:on_submit(idx, choice)
    if not choice then return end
    choice.animal.marked = not choice.animal.marked
    self:refresh()
end

function AnimalBreeder:get_selected()
    local _, choice = self.subviews.list:getSelected()
    if choice then
        return choice.animal
    end
    return nil
end

function AnimalBreeder:get_marked_or_selected()
    local marked = {}
    for _, a in ipairs(self.filtered_animals) do
        if a.marked then
            table.insert(marked, a)
        end
    end
    if #marked > 0 then
        return marked
    end
    local sel = self:get_selected()
    if sel then
        return {sel}
    end
    return {}
end

-- Range selection with shift-click
function AnimalBreeder:onInput(keys)
    if keys._MOUSE_L then
        local list = self.subviews.list
        local idx = list:getIdxUnderMouse()
        if idx then
            -- Check for shift+click for range selection
            local mods = dfhack.internal.getModifiers()
            if mods and mods.shift and self.last_click_idx then
                -- Range select from last click to current
                local start_idx = math.min(self.last_click_idx, idx)
                local end_idx = math.max(self.last_click_idx, idx)
                local choices = list:getChoices()
                for i = start_idx, end_idx do
                    if choices[i] and choices[i].animal then
                        choices[i].animal.marked = true
                    end
                end
                self:refresh()
                return true
            else
                -- Regular click - just track position
                self.last_click_idx = idx
            end
        end
    end
    return AnimalBreeder.super.onInput(self, keys)
end

function AnimalBreeder:onRenderFrame(dc, rect)
    AnimalBreeder.super.onRenderFrame(self, dc, rect)
end

function AnimalBreeder:do_toggle_mark()
    local idx, choice = self.subviews.list:getSelected()
    if not choice then return end
    
    local keys = dfhack.internal.getModifiers()
    if keys.shift and self.last_click_idx then
        -- Range mark
        local start_idx = math.min(self.last_click_idx, idx)
        local end_idx = math.max(self.last_click_idx, idx)
        local choices = self.subviews.list:getChoices()
        for i = start_idx, end_idx do
            if choices[i] and choices[i].animal then
                choices[i].animal.marked = true
            end
        end
    else
        choice.animal.marked = not choice.animal.marked
    end
    
    self.last_click_idx = idx
    self:refresh()
end

function AnimalBreeder:do_mark_all()
    local choices = self.subviews.list:getChoices()
    for _, c in ipairs(choices) do
        if c.animal then
            c.animal.marked = true
        end
    end
    self:refresh()
end

function AnimalBreeder:do_unmark_all()
    for _, a in ipairs(self.filtered_animals) do
        a.marked = false
    end
    self:refresh()
end

function AnimalBreeder:do_name()
    local targets = self:get_marked_or_selected()
    if #targets == 0 then return end
    
    local current = targets[1].name or ""
    dlg.showInputPrompt(
        "Set Name",
        string.format("Enter name for %d animal(s):", #targets),
        COLOR_WHITE,
        current,
        function(text)
            for _, a in ipairs(targets) do
                local new_nick = make_nickname(text, a.tag)
                dfhack.units.setNickname(a.unit, new_nick)
            end
            self:refresh()
        end
    )
end

function AnimalBreeder:do_tag()
    local targets = self:get_marked_or_selected()
    if #targets == 0 then return end
    
    local current = targets[1].tag or ""
    dlg.showInputPrompt(
        "Set Tag",
        string.format("Enter tag for %d animal(s) (e.g. [BREED]):", #targets),
        COLOR_WHITE,
        current,
        function(text)
            -- Ensure tag format
            if text and text ~= "" then
                if not text:match("^%[") then
                    text = "[" .. text .. "]"
                end
            end
            for _, a in ipairs(targets) do
                local new_nick = make_nickname(a.name, text)
                dfhack.units.setNickname(a.unit, new_nick)
            end
            self:refresh()
        end
    )
end

function AnimalBreeder:do_clear_name()
    local targets = self:get_marked_or_selected()
    if #targets == 0 then return end
    
    for _, a in ipairs(targets) do
        dfhack.units.setNickname(a.unit, "")
    end
    self:refresh()
end

function AnimalBreeder:do_geld()
    local targets = self:get_marked_or_selected()
    if #targets == 0 then return end
    
    local to_geld = {}
    for _, a in ipairs(targets) do
        if a.sex == "M" and not a.gelded then
            table.insert(to_geld, a)
        end
    end
    
    if #to_geld == 0 then
        dlg.showMessage("Geld", "No ungelled males in selection.", COLOR_YELLOW)
        return
    end
    
    showConfirm(
        "Confirm Geld",
        string.format("Geld %d male(s)? This cannot be undone.", #to_geld),
        function()
            for _, a in ipairs(to_geld) do
                a.unit.flags3.gelded = true
            end
            self:refresh()
        end
    )
end

function AnimalBreeder:do_cage()
    local targets = self:get_marked_or_selected()
    if #targets == 0 then return end
    
    local to_cage = {}
    for _, a in ipairs(targets) do
        if not a.caged then
            table.insert(to_cage, a)
        end
    end
    
    if #to_cage == 0 then
        dlg.showMessage("Cage", "All selected animals are already caged.", COLOR_YELLOW)
        return
    end
    
    local empty_cages = find_empty_cages()
    if #empty_cages < #to_cage then
        dlg.showMessage("Cage", 
            string.format("Not enough empty built cages. Need %d, have %d.", #to_cage, #empty_cages),
            COLOR_RED)
        return
    end
    
    showConfirm(
        "Confirm Cage",
        string.format("Assign %d animal(s) to cages?", #to_cage),
        function()
            for i, a in ipairs(to_cage) do
                unassign_from_zones(a.unit)  -- Remove from pastures first
                assign_to_cage(a.unit, empty_cages[i])
            end
            self:refresh()
        end
    )
end

function AnimalBreeder:do_uncage()
    local targets = self:get_marked_or_selected()
    if #targets == 0 then return end
    
    local to_uncage = {}
    for _, a in ipairs(targets) do
        if a.caged then
            table.insert(to_uncage, a)
        end
    end
    
    if #to_uncage == 0 then
        dlg.showMessage("Uncage", "No caged animals in selection.", COLOR_YELLOW)
        return
    end
    
    showConfirm(
        "Confirm Uncage",
        string.format("Remove %d animal(s) from cage assignments?", #to_uncage),
        function()
            for _, a in ipairs(to_uncage) do
                unassign_from_cage(a.unit)
            end
            self:refresh()
        end
    )
end

function AnimalBreeder:do_butcher()
    local targets = self:get_marked_or_selected()
    if #targets == 0 then return end
    
    local to_butcher = {}
    for _, a in ipairs(targets) do
        if not a.slaughter then
            table.insert(to_butcher, a)
        end
    end
    
    if #to_butcher == 0 then
        dlg.showMessage("Butcher", "All selected animals are already marked.", COLOR_YELLOW)
        return
    end
    
    showConfirm(
        "Confirm Butcher",
        string.format("Mark %d animal(s) for slaughter?", #to_butcher),
        function()
            for _, a in ipairs(to_butcher) do
                a.unit.flags2.slaughter = true
            end
            self:refresh()
        end
    )
end

function AnimalBreeder:do_unbutcher()
    local targets = self:get_marked_or_selected()
    if #targets == 0 then return end
    
    local to_unmark = {}
    for _, a in ipairs(targets) do
        if a.slaughter then
            table.insert(to_unmark, a)
        end
    end
    
    if #to_unmark == 0 then
        dlg.showMessage("Unbutcher", "No animals marked for slaughter in selection.", COLOR_YELLOW)
        return
    end
    
    for _, a in ipairs(to_unmark) do
        a.unit.flags2.slaughter = false
    end
    self:refresh()
end

function AnimalBreeder:do_export()
    if not self.current_species then
        dlg.showMessage("Export", "No species selected.", COLOR_RED)
        return
    end
    
    -- Generate default filename with species name
    local default_name = "animal-breeder-" .. (self.current_species:lower():gsub(" ", "-"))
    
    dlg.showInputPrompt(
        "Export CSV",
        "Enter filename (without .csv):",
        COLOR_WHITE,
        default_name,
        function(input)
            if not input or input == "" then return end
            self:do_export_to_file(input .. ".csv")
        end
    )
end

function AnimalBreeder:do_export_to_file(filename)
    local file = io.open(filename, "w")
    if not file then
        dlg.showMessage("Export", "Failed to create file: " .. filename, COLOR_RED)
        return
    end
    
    -- Header
    file:write("ID,Race,Sex,Adult,Gelded,Caged,Slaughter,Generation,Name,Tag,Mother_ID,Father_ID,")
    file:write("STR,AGI,TGH,END,REC,DIS,WIL,FOC,SPA,KIN,")
    file:write("PHYS_AVG,PHYS_PCT,MENT_AVG,MENT_PCT,ALL_AVG,ALL_PCT,HERD_RANK,")
    file:write("BODY_HEIGHT,BODY_BROADNESS,BODY_LENGTH,BODY_SIZE_PCT\n")
    
    for _, a in ipairs(self.filtered_animals) do
        file:write(string.format("%d,%s,%s,%s,%s,%s,%s,%d,%s,%s,%d,%d,",
            a.id, a.race, a.sex, 
            a.adult and "Y" or "N",
            a.gelded and "Y" or "N",
            a.caged and "Y" or "N",
            a.slaughter and "Y" or "N",
            a.generation or 0,
            a.name or "", a.tag or "",
            a.mother_id, a.father_id
        ))
        file:write(string.format("%d,%d,%d,%d,%d,%d,%d,%d,%d,%d,",
            a.attrs.STRENGTH or 0, a.attrs.AGILITY or 0,
            a.attrs.TOUGHNESS or 0, a.attrs.ENDURANCE or 0,
            a.attrs.RECUPERATION or 0, a.attrs.DISEASE_RESISTANCE or 0,
            a.attrs.WILLPOWER or 0, a.attrs.FOCUS or 0,
            a.attrs.SPATIAL_SENSE or 0, a.attrs.KINESTHETIC_SENSE or 0
        ))
        file:write(string.format("%d,%d,%d,%d,%d,%d,%d,",
            a.attrs.phys_score, a.phys_pct,
            a.attrs.mental_score, a.ment_pct,
            a.attrs.all_score, a.all_pct, a.herd_rank
        ))
        file:write(string.format("%d,%d,%d,%d\n",
            a.body_height or 100, a.body_broadness or 100,
            a.body_length or 100, a.body_size_pct or 100
        ))
    end
    
    file:close()
    dlg.showMessage("Export", 
        string.format("Exported %d animals to %s", #self.filtered_animals, filename),
        COLOR_GREEN)
end

-------------------------------------------------
-- Main
-------------------------------------------------

local screen = nil

function main(args)
    if screen then
        screen:dismiss()
    end
    
    local parsed_args = {}
    if args then
        for _, arg in ipairs(args) do
            if arg == '--detailed' or arg == '-d' then
                parsed_args.detailed = true
            end
        end
    end
    
    screen = AnimalBreeder{init_args=parsed_args}
    screen:show()
end

if not dfhack_flags.module then
    main{...}
end