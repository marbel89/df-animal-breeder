-- Attribute-based animal breeding manager
--@module = true
--@enable = false

--[====[

animal-breeder
==============

A GUI tool for managing animal breeding programs based on genetic attributes.
Displays all physical and relevant mental attributes with color-coding and percentile
rankings to help identify the best breeding stock.

Sadly, breeding does not work vor version 50.

Usage::

    animal-breeder

Keybinding example (add to dfhack-config/init/dfhack.init)::

    keybinding add Alt-B@dwarfmode/Default animal-breeder

]====]

local gui = require('gui')
local widgets = require('gui.widgets')
local dlg = require('gui.dialogs')

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
                if is_empty then
                    table.insert(cages, bld)
                end
            end
        end
    end
    return cages
end

local function assign_to_cage(unit, cage)
    if cage.assigned_units then
        cage.assigned_units:insert('#', unit.id)
        return true
    end
    return false
end

local function remove_from_cage(unit)
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

-------------------------------------------------
-- Data Functions
-------------------------------------------------

local function is_valid_animal(unit)
    if not unit then return false end
    if not dfhack.units.isActive(unit) then return false end
    if dfhack.units.isDead(unit) then return false end
    if dfhack.units.isCitizen(unit) then return false end
    if not dfhack.units.isTame(unit) then return false end
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
        end
        return
    end
    
    local phys_sorted = {}
    local ment_sorted = {}
    local all_sorted = {}
    for _, a in ipairs(animals) do
        table.insert(phys_sorted, a.attrs.phys_score)
        table.insert(ment_sorted, a.attrs.mental_score)
        table.insert(all_sorted, a.attrs.all_score)
    end
    table.sort(phys_sorted)
    table.sort(ment_sorted)
    table.sort(all_sorted)
    
    for _, a in ipairs(animals) do
        local phys_rank, ment_rank, all_rank = 1, 1, 1
        for i, v in ipairs(phys_sorted) do
            if a.attrs.phys_score >= v then phys_rank = i end
        end
        for i, v in ipairs(ment_sorted) do
            if a.attrs.mental_score >= v then ment_rank = i end
        end
        for i, v in ipairs(all_sorted) do
            if a.attrs.all_score >= v then all_rank = i end
        end
        a.phys_pct = math.floor((phys_rank / #animals) * 100)
        a.ment_pct = math.floor((ment_rank / #animals) * 100)
        a.all_pct = math.floor((all_rank / #animals) * 100)
    end
end

-------------------------------------------------
-- Export Functions
-------------------------------------------------

local function export_to_csv(animals, species_name)
    local lines = {}
    
    -- Header
    table.insert(lines, "ID,Species,Sex,Age,Gelded,Caged,Butcher,Name,Tag,Mother_ID,Father_ID,STR,AGI,TGH,END,REC,DIS,WIL,FOC,SPA,KIN,PHYS,PHYS_PCT,MENT,MENT_PCT,ALL,ALL_PCT")
    
    -- Data rows
    for _, a in ipairs(animals) do
        local row = string.format("%d,%s,%s,%s,%s,%s,%s,%s,%s,%d,%d,%d,%d,%d,%d,%d,%d,%d,%d,%d,%d,%d,%d,%d,%d,%d,%d",
            a.id,
            a.race,
            a.sex,
            a.adult and "Adult" or "Juvenile",
            a.gelded and "Yes" or "No",
            a.caged and "Yes" or "No",
            a.slaughter and "Yes" or "No",
            a.name or "",
            a.tag or "",
            a.mother_id,
            a.father_id,
            a.attrs.STRENGTH or 0,
            a.attrs.AGILITY or 0,
            a.attrs.TOUGHNESS or 0,
            a.attrs.ENDURANCE or 0,
            a.attrs.RECUPERATION or 0,
            a.attrs.DISEASE_RESISTANCE or 0,
            a.attrs.WILLPOWER or 0,
            a.attrs.FOCUS or 0,
            a.attrs.SPATIAL_SENSE or 0,
            a.attrs.KINESTHETIC_SENSE or 0,
            a.attrs.phys_score,
            a.phys_pct,
            a.attrs.mental_score,
            a.ment_pct,
            a.attrs.all_score,
            a.all_pct
        )
        table.insert(lines, row)
    end
    
    return table.concat(lines, "\n")
end

-------------------------------------------------
-- Main Screen
-------------------------------------------------

AnimalBreeder = defclass(AnimalBreeder, gui.ZScreen)
AnimalBreeder.ATTRS{focus_path = 'animal-breeder'}

function AnimalBreeder:init()
    self.all_animals = gather_all_animals()
    self.species_list = get_species_list(self.all_animals)
    
    self.current_species = nil
    if animal_breeder_last_species then
        for _, sp in ipairs(self.species_list) do
            if sp.name == animal_breeder_last_species then
                self.current_species = animal_breeder_last_species
                break
            end
        end
    end
    if not self.current_species and self.species_list[1] then
        self.current_species = self.species_list[1].name
    end
    
    self.filtered_animals = {}
    self.last_click_idx = nil
    
    -- Filters
    self.show_males = true
    self.show_females = true
    self.show_gelded = true
    self.show_caged = true
    self.show_adults = true
    self.show_juveniles = true
    self.filter_attr = "NONE"
    self.filter_min = 0
    self.sort_attr = "all_score"
    self.sort_desc = true
    self.name_filter = ""
    
    -- Build filter attr options
    local attr_options = {{label="NONE", value="NONE"}}
    table.insert(attr_options, {label="PHYS", value="phys_score"})
    table.insert(attr_options, {label="MENT", value="mental_score"})
    table.insert(attr_options, {label="ALL", value="all_score"})
    for _, attr in ipairs(ALL_ATTRS) do
        table.insert(attr_options, {label=ATTR_SHORT[attr], value=attr})
    end
    
    self:addviews{
        widgets.Window{
            frame = {w=148, h=50},
            frame_title = 'Animal Breeder',
            resizable = true,
            subviews = {
                -- Row 1: Species selector + text filter
                widgets.Panel{
                    frame = {t=0, l=0, r=0, h=1},
                    subviews = {
                        widgets.Label{frame={t=0,l=0}, text="Species:"},
                        widgets.HotkeyLabel{
                            view_id = 'species_btn',
                            frame = {t=0, l=9, w=30},
                            label = function() 
                                if self.current_species then
                                    local count = 0
                                    for _, a in ipairs(self.all_animals) do
                                        if a.race == self.current_species then count = count + 1 end
                                    end
                                    return self.current_species .. " (" .. count .. ")"
                                end
                                return "(none)"
                            end,
                            text_pen = COLOR_LIGHTCYAN,
                            on_activate = function() self:show_species_picker() end,
                        },
                        widgets.Label{frame={t=0,l=42}, text="Search:"},
                        widgets.HotkeyLabel{
                            view_id = 'search_btn',
                            frame = {t=0, l=50, w=20},
                            label = function()
                                if self.name_filter == "" then
                                    return "(click)"
                                else
                                    return '"' .. self.name_filter .. '"'
                                end
                            end,
                            text_pen = function()
                                return self.name_filter == "" and COLOR_GRAY or COLOR_LIGHTGREEN
                            end,
                            on_activate = function() self:show_text_filter() end,
                        },
                        widgets.HotkeyLabel{
                            frame = {t=0, l=72, w=3},
                            label = "[X]",
                            text_pen = COLOR_LIGHTRED,
                            on_activate = function() 
                                self.name_filter = ""
                                self:refresh()
                            end,
                        },
                        widgets.Label{
                            frame = {t=0, l=80},
                            text = {{text=function() return string.format("Marked: %d  Cages: %d", self:count_marked(), #find_empty_cages()) end, pen=COLOR_YELLOW}},
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
                            label = "M",
                            initial_option = true,
                            on_change = function(val) self.show_males = val; self:refresh() end,
                        },
                        widgets.ToggleHotkeyLabel{
                            view_id = 'tog_female',
                            frame = {t=0, l=8},
                            label = "F",
                            initial_option = true,
                            on_change = function(val) self.show_females = val; self:refresh() end,
                        },
                        widgets.ToggleHotkeyLabel{
                            view_id = 'tog_adult',
                            frame = {t=0, l=16},
                            label = "Adult",
                            initial_option = true,
                            on_change = function(val) self.show_adults = val; self:refresh() end,
                        },
                        widgets.ToggleHotkeyLabel{
                            view_id = 'tog_juv',
                            frame = {t=0, l=29},
                            label = "Juv",
                            initial_option = true,
                            on_change = function(val) self.show_juveniles = val; self:refresh() end,
                        },
                        widgets.ToggleHotkeyLabel{
                            view_id = 'tog_gelded',
                            frame = {t=0, l=40},
                            label = "Geld",
                            initial_option = true,
                            on_change = function(val) self.show_gelded = val; self:refresh() end,
                        },
                        widgets.ToggleHotkeyLabel{
                            view_id = 'tog_caged',
                            frame = {t=0, l=52},
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
                        widgets.HotkeyLabel{
                            frame = {t=0, l=110},
                            label = "Export CSV",
                            key = "CUSTOM_E",
                            on_activate = function() self:do_export() end,
                        },
                    },
                },
                -- Row 3: Clickable column headers
                widgets.Panel{
                    frame = {t=4, l=0, r=0, h=1},
                    subviews = {
                        widgets.Label{frame={t=0,l=0,w=2}, text="  ", text_pen=COLOR_LIGHTBLUE},
                        widgets.Label{frame={t=0,l=2,w=6}, text="ID", text_pen=COLOR_LIGHTBLUE, on_click=function() self:set_sort("id") end},
                        widgets.Label{frame={t=0,l=9,w=5}, text="Sex", text_pen=COLOR_LIGHTBLUE, on_click=function() self:set_sort("sex") end},
                        widgets.Label{frame={t=0,l=15,w=8}, text="Status", text_pen=COLOR_LIGHTBLUE},
                        widgets.Label{frame={t=0,l=24,w=10}, text="Name", text_pen=COLOR_LIGHTBLUE, on_click=function() self:set_sort("name") end},
                        widgets.Label{frame={t=0,l=35,w=9}, text="Tag", text_pen=COLOR_LIGHTBLUE, on_click=function() self:set_sort("tag") end},
                        -- Physical attrs
                        widgets.Label{frame={t=0,l=45,w=5}, text="STR", text_pen=COLOR_LIGHTCYAN, on_click=function() self:set_sort("STRENGTH") end},
                        widgets.Label{frame={t=0,l=51,w=5}, text="AGI", text_pen=COLOR_LIGHTCYAN, on_click=function() self:set_sort("AGILITY") end},
                        widgets.Label{frame={t=0,l=57,w=5}, text="TGH", text_pen=COLOR_LIGHTCYAN, on_click=function() self:set_sort("TOUGHNESS") end},
                        widgets.Label{frame={t=0,l=63,w=5}, text="END", text_pen=COLOR_LIGHTCYAN, on_click=function() self:set_sort("ENDURANCE") end},
                        widgets.Label{frame={t=0,l=69,w=5}, text="REC", text_pen=COLOR_LIGHTCYAN, on_click=function() self:set_sort("RECUPERATION") end},
                        widgets.Label{frame={t=0,l=75,w=5}, text="DIS", text_pen=COLOR_LIGHTCYAN, on_click=function() self:set_sort("DISEASE_RESISTANCE") end},
                        -- Mental attrs
                        widgets.Label{frame={t=0,l=81,w=5}, text="WIL", text_pen=COLOR_LIGHTMAGENTA, on_click=function() self:set_sort("WILLPOWER") end},
                        widgets.Label{frame={t=0,l=87,w=5}, text="FOC", text_pen=COLOR_LIGHTMAGENTA, on_click=function() self:set_sort("FOCUS") end},
                        widgets.Label{frame={t=0,l=93,w=5}, text="SPA", text_pen=COLOR_LIGHTMAGENTA, on_click=function() self:set_sort("SPATIAL_SENSE") end},
                        widgets.Label{frame={t=0,l=99,w=5}, text="KIN", text_pen=COLOR_LIGHTMAGENTA, on_click=function() self:set_sort("KINESTHETIC_SENSE") end},
                        -- Scores
                        widgets.Label{frame={t=0,l=105,w=5}, text="PHYS", text_pen=COLOR_GREEN, on_click=function() self:set_sort("phys_score") end},
                        widgets.Label{frame={t=0,l=111,w=4}, text="%", text_pen=COLOR_GREEN},
                        widgets.Label{frame={t=0,l=116,w=5}, text="MENT", text_pen=COLOR_YELLOW, on_click=function() self:set_sort("mental_score") end},
                        widgets.Label{frame={t=0,l=122,w=4}, text="%", text_pen=COLOR_YELLOW},
                        widgets.Label{frame={t=0,l=127,w=5}, text="ALL", text_pen=COLOR_WHITE, on_click=function() self:set_sort("all_score") end},
                        widgets.Label{frame={t=0,l=133,w=4}, text="%", text_pen=COLOR_WHITE},
                    },
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
                        widgets.HotkeyLabel{frame={t=0,l=0}, label="Zoom", key="SELECT", on_activate=function() self:do_zoom() end},
                        widgets.HotkeyLabel{frame={t=0,l=12}, label="Mark", key="CUSTOM_M", on_activate=function() self:do_toggle_mark() end},
                        widgets.HotkeyLabel{frame={t=0,l=24}, label="MarkAll", key="CUSTOM_A", on_activate=function() self:do_mark_all() end},
                        widgets.HotkeyLabel{frame={t=0,l=38}, label="Unmark", key="CUSTOM_U", on_activate=function() self:do_unmark_all() end},
                        widgets.HotkeyLabel{frame={t=1,l=0}, label="Name", key="CUSTOM_N", on_activate=function() self:do_name() end},
                        widgets.HotkeyLabel{frame={t=1,l=12}, label="Tag", key="CUSTOM_T", on_activate=function() self:do_tag() end},
                        widgets.HotkeyLabel{frame={t=1,l=22}, label="Geld", key="CUSTOM_G", on_activate=function() self:do_geld() end},
                        widgets.HotkeyLabel{frame={t=1,l=33}, label="Cage", key="CUSTOM_X", on_activate=function() self:do_cage() end},
                        widgets.HotkeyLabel{frame={t=1,l=44}, label="Uncage", key="CUSTOM_R", on_activate=function() self:do_uncage() end},
                        widgets.HotkeyLabel{frame={t=1,l=57}, label="Butcher", key="CUSTOM_B", on_activate=function() self:do_butcher() end},
                        widgets.HotkeyLabel{frame={t=1,l=71}, label="Unbutch", key="CUSTOM_V", on_activate=function() self:do_unbutcher() end},
                        widgets.HotkeyLabel{frame={t=1,l=85}, label="Clear", key="CUSTOM_C", on_activate=function() self:do_clear_name() end},
                        widgets.Label{frame={t=0,l=55}, text="[Shift+Click = range]", text_pen=COLOR_GRAY},
                    },
                },
                -- Close button
                widgets.HotkeyLabel{frame={b=0,l=0}, label="Close", key="LEAVESCREEN", on_activate=function() self:dismiss() end},
            }
        }
    }
    
    self:update_species()
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
            table.insert(self.filtered_animals, a)
        end
    end
    
    calculate_percentiles(self.filtered_animals)
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

function AnimalBreeder:refresh()
    local display = self:get_display_animals()
    local choices = {}
    
    for i, a in ipairs(display) do
        local mark_char = a.marked and "*" or " "
        
        -- Combined Sex display: M/F + Adult/Juv
        local sex_age = a.sex .. (a.adult and "-A" or "-J")
        
        -- Status flags as readable short codes
        local status_parts = {}
        if a.gelded then table.insert(status_parts, "Gld") end
        if a.caged then table.insert(status_parts, "Cge") end
        if a.slaughter then table.insert(status_parts, "But") end
        local status_str = #status_parts > 0 and table.concat(status_parts, " ") or "-"
        
        local name_display = a.name or "-"
        if #name_display > 9 then name_display = name_display:sub(1,8) .. "." end
        
        local tag_display = a.tag or "-"
        if #tag_display > 8 then tag_display = tag_display:sub(1,7) .. "." end
        
        -- Colors
        local sex_color = a.sex == "F" and COLOR_LIGHTMAGENTA or COLOR_LIGHTCYAN
        if not a.adult then sex_color = COLOR_BROWN end
        if a.slaughter then sex_color = COLOR_LIGHTRED end
        
        local status_color = COLOR_GRAY
        if a.slaughter then status_color = COLOR_RED
        elseif a.caged then status_color = COLOR_YELLOW
        elseif a.gelded then status_color = COLOR_BROWN
        end
        
        -- Build colored line
        local line = {
            {text=mark_char .. " ", pen=a.marked and COLOR_YELLOW or COLOR_WHITE},
            {text=string.format("%-6d ", a.id), pen=COLOR_WHITE},
            {text=string.format("%-5s", sex_age), pen=sex_color},
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
            -- Scores with colors
            {text=string.format("%5d ", a.attrs.phys_score), pen=get_attr_color(a.attrs.phys_score)},
            {text=string.format("%3d%% ", a.phys_pct), pen=get_pct_color(a.phys_pct)},
            {text=string.format("%5d ", a.attrs.mental_score), pen=get_attr_color(a.attrs.mental_score)},
            {text=string.format("%3d%% ", a.ment_pct), pen=get_pct_color(a.ment_pct)},
            {text=string.format("%5d ", a.attrs.all_score), pen=get_attr_color(a.attrs.all_score)},
            {text=string.format("%3d%%", a.all_pct), pen=get_pct_color(a.all_pct)},
        }
        
        table.insert(choices, {
            text = line,
            data = a,
        })
    end
    self.subviews.list:setChoices(choices)
    
    local sort_dir = self.sort_desc and "desc" or "asc"
    local sort_name = ATTR_SHORT[self.sort_attr] or self.sort_attr
    local status = string.format("Showing %d of %d  |  Sort: %s (%s)", 
        #display, #self.filtered_animals, sort_name, sort_dir)
    if self.filter_attr ~= "NONE" and self.filter_min > 0 then
        local attr_name = ATTR_SHORT[self.filter_attr] or self.filter_attr
        status = status .. string.format("  |  Filter: %s >= %d", attr_name, self.filter_min)
    end
    self.subviews.status:setText({{text=status, pen=COLOR_GRAY}})
end

function AnimalBreeder:do_export()
    local display = self:get_display_animals()
    if #display == 0 then
        dlg.showMessage("Export", "No animals to export.", COLOR_YELLOW)
        return
    end
    
    local csv = export_to_csv(display, self.current_species)
    
    -- Try clipboard first
    local success = false
    if dfhack.internal and dfhack.internal.setClipboardTextCp437 then
        success = pcall(function()
            dfhack.internal.setClipboardTextCp437(csv)
        end)
    end
    
    -- Also save to file
    local filename = "animal-breeder-export.csv"
    local file = io.open(filename, "w")
    if file then
        file:write(csv)
        file:close()
        
        if success then
            dlg.showMessage("Export Complete", 
                string.format("Exported %d animals.\n\nCopied to clipboard!\nAlso saved to: %s\n\nIncludes Mother_ID and Father_ID columns for generation tracking.", 
                    #display, filename), 
                COLOR_GREEN)
        else
            dlg.showMessage("Export Complete", 
                string.format("Exported %d animals.\n\nSaved to: %s\n(Clipboard not available)\n\nIncludes Mother_ID and Father_ID columns for generation tracking.", 
                    #display, filename), 
                COLOR_GREEN)
        end
    else
        dlg.showMessage("Export Failed", "Could not write file.", COLOR_LIGHTRED)
    end
end

function AnimalBreeder:onInput(keys)
    if keys._MOUSE_L then
        local list = self.subviews.list
        local idx = list:getIdxUnderMouse()
        if idx then
            if keys._MOUSE_L_DOWN and dfhack.internal.getModifiers().shift then
                if self.last_click_idx and self.last_click_idx ~= idx then
                    local start_idx = math.min(self.last_click_idx, idx)
                    local end_idx = math.max(self.last_click_idx, idx)
                    local choices = list:getChoices()
                    for i = start_idx, end_idx do
                        if choices[i] and choices[i].data then
                            choices[i].data.marked = true
                        end
                    end
                    self:refresh()
                    return true
                end
            else
                self.last_click_idx = idx
            end
        end
    end
    return AnimalBreeder.super.onInput(self, keys)
end

function AnimalBreeder:on_select(idx, choice)
    if idx then
        self.last_click_idx = idx
    end
end

function AnimalBreeder:on_submit(idx, choice)
    self:do_zoom()
end

function AnimalBreeder:get_selected()
    local idx, choice = self.subviews.list:getSelected()
    if choice then return choice.data end
    return nil
end

function AnimalBreeder:get_targets()
    local marked = {}
    for _, a in ipairs(self.filtered_animals) do
        if a.marked then table.insert(marked, a) end
    end
    if #marked > 0 then return marked end
    
    local sel = self:get_selected()
    if sel then return {sel} end
    return {}
end

function AnimalBreeder:do_zoom()
    local animal = self:get_selected()
    if animal and animal.unit.pos then
        dfhack.gui.revealInDwarfmodeMap(animal.unit.pos, true)
    end
end

function AnimalBreeder:do_toggle_mark()
    local animal = self:get_selected()
    if animal then
        animal.marked = not animal.marked
        self:refresh()
    end
end

function AnimalBreeder:do_mark_all()
    local display = self:get_display_animals()
    for _, a in ipairs(display) do
        a.marked = true
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
    local targets = self:get_targets()
    if #targets == 0 then return end
    
    if #targets > 1 then
        dlg.showMessage("Name", "Cannot name multiple animals at once.\nUnmark others first.", COLOR_YELLOW)
        return
    end
    
    local animal = targets[1]
    dlg.showInputPrompt(
        "Name Animal",
        "Enter name for " .. animal.race .. " (ID:" .. animal.id .. "):\n(Tag will be preserved)",
        COLOR_WHITE,
        animal.name or "",
        function(text)
            if text then
                local new_nick = make_nickname(text ~= "" and text or nil, animal.tag)
                animal.unit.name.nickname = new_nick
                animal.nickname = new_nick
                animal.name = text ~= "" and text or nil
                self:refresh()
            end
        end
    )
end

function AnimalBreeder:do_tag()
    local targets = self:get_targets()
    if #targets == 0 then return end
    
    local tags = {
        "[BREED]", "[ISOLATE]", "[STUD]", "[GELD]", 
        "[KEEP]", "[SELL]", "[WAR]", "[HUNT]", "[CAGE]", "[BUTCHER]",
        "(clear tag)", "(custom...)"
    }
    local choices = {}
    for _, tag in ipairs(tags) do
        table.insert(choices, {text = tag, tag = tag})
    end
    
    local desc = #targets == 1 
        and string.format("%s (ID:%d)", targets[1].race, targets[1].id)
        or string.format("%d animals", #targets)
    
    dlg.showListPrompt(
        "Tag Animal(s)",
        "Select tag for " .. desc .. ":",
        COLOR_WHITE,
        choices,
        function(idx, choice)
            if not choice then return end
            
            if choice.tag == "(custom...)" then
                dlg.showInputPrompt(
                    "Custom Tag",
                    "Enter custom tag (without brackets):",
                    COLOR_WHITE,
                    "",
                    function(text)
                        if text and text ~= "" then
                            local custom_tag = "[" .. text:upper() .. "]"
                            for _, animal in ipairs(targets) do
                                local new_nick = make_nickname(animal.name, custom_tag)
                                animal.unit.name.nickname = new_nick
                                animal.nickname = new_nick
                                animal.tag = custom_tag
                            end
                            self:refresh()
                        end
                    end
                )
            elseif choice.tag == "(clear tag)" then
                for _, animal in ipairs(targets) do
                    local new_nick = make_nickname(animal.name, nil)
                    animal.unit.name.nickname = new_nick
                    animal.nickname = new_nick
                    animal.tag = nil
                end
                self:refresh()
            else
                for _, animal in ipairs(targets) do
                    local new_nick = make_nickname(animal.name, choice.tag)
                    animal.unit.name.nickname = new_nick
                    animal.nickname = new_nick
                    animal.tag = choice.tag
                end
                self:refresh()
            end
        end
    )
end

function AnimalBreeder:do_geld()
    local targets = self:get_targets()
    if #targets == 0 then return end
    
    local valid = {}
    for _, a in ipairs(targets) do
        if a.sex == "M" and not a.gelded then
            table.insert(valid, a)
        end
    end
    
    if #valid == 0 then
        dlg.showMessage("Cannot Geld", "No valid targets.\nOnly intact males can be gelded.", COLOR_YELLOW)
        return
    end
    
    local desc = #valid == 1
        and string.format("this %s (ID:%d)", valid[1].race, valid[1].id)
        or string.format("these %d males", #valid)
    
    dlg.showYesNoPrompt(
        "Geld Animal(s)",
        "Geld " .. desc .. "?\n\nThis cannot be undone!",
        COLOR_YELLOW,
        function()
            for _, animal in ipairs(valid) do
                animal.unit.flags3.gelded = true
                animal.gelded = true
            end
            self:refresh()
        end
    )
end

function AnimalBreeder:do_cage()
    local targets = self:get_targets()
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
        dlg.showMessage("Not Enough Cages", 
            string.format("Need %d cages but only %d empty cages available.\n\nBuild more cages first.", 
                #to_cage, #empty_cages), 
            COLOR_LIGHTRED)
        return
    end
    
    local desc = #to_cage == 1
        and string.format("this %s (ID:%d)", to_cage[1].race, to_cage[1].id)
        or string.format("these %d animals", #to_cage)
    
    dlg.showYesNoPrompt(
        "Cage Animal(s)",
        "Assign " .. desc .. " to cage(s)?\n\nA dwarf will haul them to the cage.",
        COLOR_WHITE,
        function()
            for i, animal in ipairs(to_cage) do
                assign_to_cage(animal.unit, empty_cages[i])
                animal.caged = true
            end
            self:refresh()
        end
    )
end

function AnimalBreeder:do_uncage()
    local targets = self:get_targets()
    if #targets == 0 then return end
    
    local to_uncage = {}
    for _, a in ipairs(targets) do
        if a.caged then
            table.insert(to_uncage, a)
        end
    end
    
    if #to_uncage == 0 then
        dlg.showMessage("Uncage", "No selected animals are caged.", COLOR_YELLOW)
        return
    end
    
    local desc = #to_uncage == 1
        and string.format("this %s (ID:%d)", to_uncage[1].race, to_uncage[1].id)
        or string.format("these %d animals", #to_uncage)
    
    dlg.showYesNoPrompt(
        "Uncage Animal(s)",
        "Remove " .. desc .. " from cage assignment?",
        COLOR_WHITE,
        function()
            for _, animal in ipairs(to_uncage) do
                remove_from_cage(animal.unit)
                animal.caged = false
            end
            self:refresh()
        end
    )
end

function AnimalBreeder:do_butcher()
    local targets = self:get_targets()
    if #targets == 0 then return end
    
    local to_butcher = {}
    for _, a in ipairs(targets) do
        if not a.slaughter then
            table.insert(to_butcher, a)
        end
    end
    
    if #to_butcher == 0 then
        dlg.showMessage("Butcher", "All selected animals are already marked for slaughter.", COLOR_YELLOW)
        return
    end
    
    local desc = #to_butcher == 1
        and string.format("this %s (ID:%d)", to_butcher[1].race, to_butcher[1].id)
        or string.format("these %d animals", #to_butcher)
    
    dlg.showYesNoPrompt(
        "Butcher Animal(s)",
        "Mark " .. desc .. " for slaughter?\n\nA dwarf will butcher them at a butcher's shop.",
        COLOR_LIGHTRED,
        function()
            for _, animal in ipairs(to_butcher) do
                animal.unit.flags2.slaughter = true
                animal.slaughter = true
            end
            self:refresh()
        end
    )
end

function AnimalBreeder:do_unbutcher()
    local targets = self:get_targets()
    if #targets == 0 then return end
    
    local to_unbutcher = {}
    for _, a in ipairs(targets) do
        if a.slaughter then
            table.insert(to_unbutcher, a)
        end
    end
    
    if #to_unbutcher == 0 then
        dlg.showMessage("Unbutcher", "No selected animals are marked for slaughter.", COLOR_YELLOW)
        return
    end
    
    local desc = #to_unbutcher == 1
        and string.format("this %s (ID:%d)", to_unbutcher[1].race, to_unbutcher[1].id)
        or string.format("these %d animals", #to_unbutcher)
    
    dlg.showYesNoPrompt(
        "Cancel Slaughter",
        "Remove slaughter flag from " .. desc .. "?",
        COLOR_WHITE,
        function()
            for _, animal in ipairs(to_unbutcher) do
                animal.unit.flags2.slaughter = false
                animal.slaughter = false
            end
            self:refresh()
        end
    )
end

function AnimalBreeder:do_clear_name()
    local targets = self:get_targets()
    if #targets == 0 then return end
    
    for _, animal in ipairs(targets) do
        animal.unit.name.nickname = ""
        animal.nickname = nil
        animal.name = nil
        animal.tag = nil
    end
    self:refresh()
end

function AnimalBreeder:onDismiss()
    view = nil
end

-------------------------------------------------
-- Entry Point
-------------------------------------------------

view = view and view:raise() or AnimalBreeder{}:show()