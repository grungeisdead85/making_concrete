--@ module = true
-- making_concrete.lua
-- ==========================================
-- MAKING CONCRETE: RM MODULE
-- ==========================================
-- Concrete from what a fort already throws away (2.0, 2026-09-25).
-- A simple material module with hooks to and from other industries:
-- walls, floors and buildings in concrete, from waste that would
-- otherwise be useless, without changing how people play. It grows by
-- variety (a new recipe when a good idea comes along), not by
-- complexity.
--
-- ---- THE RECIPE ----
-- Concrete is binder, fine aggregate and coarse aggregate in roughly
-- real proportions, 1 : 2 : 3, and every ingredient is a loose item:
-- no bags, no barrels, no sand.
--   coarse   RM's gravel (REFINISH_GRAVEL_TOOL) on its stone's
--            aggregate twin, which carries AGGREGATE
--   fine     RM's dust (REFINISH_CORE_DUST) of any stone. Crushed rock
--            fines are a standard sand in real concrete (manufactured
--            sand, which replaces river sand outright), and quarry dust
--            is what crushing boulders into coarse aggregate leaves.
--   binder   this module's cement form in the material it was ground
--            from: clinker cement from the kiln's clinker, or slag
--            cement from RM's slag (blast furnace slag is a real clinker
--            substitute)
-- Gravel and dust pile up on their own from masonry through RM's
-- byproduct service, so cement is the only ingredient a player makes on
-- purpose. A mix is about six quarter boulders' worth (one cement, 25
-- dust at RM's 200 a dust, twelve gravel at 600) and makes ten blocks. A cut stone block
-- costs a quarter boulder (vanilla's mason makes four from a boulder); a
-- molded block costs half that, an eighth of a boulder of what is left
-- after its process takes its tenth, as RM's bricks and Making Fuel's
-- asphalt do (2026-10-04: the extra steps buy the yield). No minimum batch
-- and no bulk reaction.
--
-- ---- A REACTION PER CONCRETE ----
-- Three mixes in the menu, so the player chooses which concrete they get
-- (2026-10-03; until then one mix, and the mix watcher pointed each job
-- at what its inputs made, which read as random):
--   concrete          any cement, any stone dust, gravel
--   dwarven concrete  any cement, volcanic dust, gravel: pozzolana, the
--                     Roman recipe's volcanic ash. The dust slot asks for
--                     POZZOLAN, which no vanilla stone carries, so RM
--                     gives it to every IGNEOUS_EXTRUSIVE stone and to
--                     obsidian while its data is in RAM (POZZOLANA, below).
--   slag concrete     slag cement (RM's slag carries SLAG), any stone
--                     dust, gravel: blast furnace slag standing in for
--                     clinker, as it does in real cement.
-- A new concrete is a new reaction.
--
-- ---- RETIRED: THE MIX WATCHER (2026-10-03) ----
-- making-concrete-mix-watcher.lua pointed a mix job at a ghost reaction
-- once its ingredients were attached. What it learned, for any ghost swap:
--   - DF resolves a product's material when the reaction is built, not
--     when the job runs, so one reaction has one output material whatever
--     went in; GET_MATERIAL_PRODUCT reaches further only when the INPUT
--     material declares the product.
--   - Items attach against the base reaction and products resolve against
--     the ghost, so a ghost's reagents must match its base exactly: same
--     count, order, codes and quantities.
--   - A ghost is kept out of every menu by its building field alone
--     (building NONE); permissions and FORTRESS_MODE_ENABLED are not
--     visibility levers.
--   - A repeat job keeps its id and reaction name for ever, so a swapped
--     job that holds nothing again goes back to its base for its next
--     cycle, and a save can leave jobs on ghost names to sweep back.
--   - A lookup that misses before injection is never cached.
-- The three concretes are real reactions now, so no job carries a ghost
-- name: jobs saved on the old ghost codes find those codes as reactions.
--
-- ---- CLINKER IS GRAVEL ----
-- The kiln burns three flux stones and one clay into ten clinker
-- nodules, RM's gravel form in the clinker material: four boulders in,
-- two and a half out, roughly the mass limestone loses as it calcines.
-- In 1.x clinker was a boulder, which a BOULDER_ANY reagent would take
-- (the sand grinder had to refuse it). As gravel it is inert, the mix
-- cannot take it for aggregate because clinker carries no AGGREGATE
-- class, and only GRIND_CLINKER asks for it.
--
-- ---- WHAT RM PROVIDES, AND THIS MODULE ASKS FOR ----
-- GRAVEL and HEAP (with RM's slag) from RM's catalog, named in
-- the materials file's module block ("requires"), and RM's dust
-- (depends_on REFINISH_CORE_). RM injects each once for every module
-- that asks, so a load order never carries two gravels.
--
-- ---- WHAT SAND TAUGHT (1.x, retired 2026-09-25) ----
-- Sand is why this module was hard, and why 2.0 has none. Real sand is
-- a powder, and a powder in DF lives in a bag: collection yields one
-- unit per bag run, and the bag is a furniture item rather than a real
-- container, so a bag boosted to several units shows no count, and a
-- bag with its count shown stops working as a reagent. 1.x carried
-- eight sand bags, a cement bag, two gravel bags and a water barrel into
-- every mix, multiplied collected sand from one unit to four per bag so
-- bags matched (making-concrete-sand-multiply, which was missing from
-- the mod, so that multiplier never ran and logged an ERROR every
-- session), and injected a native Collect Sand button into the mason's
-- workshop. The lessons that outlive it:
--   - A wildcard POWDER reagent (no mat_id) matches any powder in a
--     bag; beside a specific cement slot DF cannot tell the slots
--     apart and matching goes non deterministic. Resolve every
--     material.
--   - Match a sentinel, not a list of reaction keys: a renamed key
--     drops out of a list silently (CRUSH_AGGREGATE became CRUSH_GRAVEL
--     and its sand patch quietly stopped).
--   - Two filters for one fact (a material AND the SOIL_SAND flag) are
--     one more way to reject a valid item.
-- The Collect Sand button's technique, native button injection into a
-- workshop's order list with its gates and its category leak guard,
-- lives on in the premigration backup:
-- making_concrete/scripts_modinstalled/making-concrete-sand-button.lua.
--
-- ARCHITECTURE:
--   Content lives in three JSON files:
--     making_concrete_materials.json: clinker and the three concretes,
--                                     and the module block's requests
--     making_concrete_tools.json:     the cement form
--     making_concrete_reactions.json: the cement reactions and the
--                                     three concretes
--   This Lua file loads them, runs value calculation if needed, asks RM
--   for POZZOLAN on volcanic stone once the module is injected, and
--   registers with RM's module engine via the listener API.
-- ==========================================
local json = require('json')
local scriptmanager = require('script-manager')

-- ---- LOG IDENTITY, DECLARED HERE ----
-- RM core does not know this module exists and must never have to, so
-- the module states its own system and subsystem. Guarded reqscript: a
-- bare top level one is a hard load time dependency.
local LOG_SYS, LOG_SUB = 'MAKING_CONCRETE', 'MODULE'
local rlog = nil
pcall(function() rlog = reqscript('refinish-log') end)

-- ==========================================
-- LOG FUNNEL
-- ==========================================
-- Every line this file writes goes through log(), in the one grammar
-- the log panel reads: SYSTEM SUBSYSTEM SUBJECT TYPE | body, composed
-- by refinish-log. The identity above is declared by the module, not
-- inferred anywhere: RM core does not know this module exists.
--
-- The panel filters on TYPE and nothing else, so each call site states
-- its own:
--   DETAIL   debugging material, shown in Debug only
--   INFO     what a player might check during play, Normal and up
--   YIELD    the module made something, Normal and up
--   faults, and the few confirmations a player wants at a glance
--   (COMPLETE, SYSTEM, ONLINE and the like), show in Quiet as well
-- TYPE comes first so no call site can drop it unnoticed: a nil TYPE
-- still renders, as UNTYPED, which shows at every Log Detail level
-- instead of being guessed at.
--
-- SUBJECT is the correlation slot: the part of the module a line is
-- about (DATA, POZZOLAN).
--
-- Every line reaches the log on disk. Filtering is the panel's job
-- alone, so there is no level check here.
--
-- No console prints. A print only appears as the direct answer to a
-- command typed into the DFHack console, and nowhere else.
-- This file used to print every message to the console and write
-- nothing to the log, so none of it reached the log panel.
-- ==========================================
local function log(typ, msg, subject)
    if not _G.refinish_log_event then return end
    local line
    if rlog then
        line = rlog.compose(LOG_SYS, LOG_SUB, subject, typ, msg)
    else
        -- The composer failed to load. Same grammar, unsanitised.
        line = string.format('%s %s %s %s | %s', LOG_SYS, LOG_SUB,
            tostring(subject or '-'), tostring(typ or 'UNTYPED'),
            tostring(msg))
    end
    _G.refinish_log_event(line)
end


-- ==========================================
-- CONFIGURATION: edit these to match your mod
-- ==========================================

-- Must match the [ID:...] in your mod's info.txt
local MODULE_ID = "making_concrete"

-- Friendly name for RM's log output
local MODULE_NAME = "Making Concrete"

-- JSON file names (relative to your mod's data/ folder)
local MATERIALS_FILE = "making_concrete_materials.json"
local REACTIONS_FILE = "making_concrete_reactions.json"
local TOOLS_FILE = "making_concrete_tools.json"


-- ==========================================
-- DO NOT EDIT BELOW THIS LINE
-- ==========================================


-- ==========================================
-- JSON LOADER
-- ==========================================
-- Reads and parses a JSON file from disk.
-- Returns the parsed Lua table, or nil on failure.
-- ==========================================
local function load_json(path)
    local file = io.open(path, "r")
    if not file then return nil end
    local content = file:read("*all")
    file:close()
    if not content or content == "" then return nil end
    local ok, parsed = pcall(json.decode, content)
    if not ok then return nil end
    return parsed
end


-- ==========================================
-- VALUE CALCULATOR
-- ==========================================
-- Computes a weighted average material value from a reaction's
-- BAR reagents. Weights are proportional to bar quantity.
--
-- Only BAR reagents contribute. Non-metal inputs like
-- flux, coal, boulders, and powders don't have meaningful
-- material values for pricing purposes.
--
-- This reads live material values from the loaded world at
-- token-call time, so alloy values correctly reflect the
-- current world's metal economy.
--
-- Returns: integer value (minimum 1)
-- ==========================================
local function calculate_weighted_value(reagents)
    local inorganics = df.global.world.raws.inorganics.all

    -- Build a value lookup from every loaded inorganic
    local value_lookup = {}
    for _, mat in ipairs(inorganics) do
        value_lookup[mat.id] = mat.material.material_value
    end

    local total_quantity = 0
    local weighted_sum = 0

    for _, rgt in ipairs(reagents) do
        -- Only count metal bar reagents: they carry the
        -- meaningful value signal for alloy pricing
        if rgt.type == "BAR" and rgt.mat_id then
            local base_val = value_lookup[rgt.mat_id] or 1
            local qty = rgt.quantity or 150
            weighted_sum = weighted_sum + (base_val * qty)
            total_quantity = total_quantity + qty
        end
    end

    if total_quantity > 0 then
        return math.floor(weighted_sum / total_quantity)
    end
    return 1
end


-- ==========================================
-- POZZOLANA: VOLCANIC DUST FOR DWARVEN CONCRETE
-- ==========================================
-- Dwarven concrete's dust slot asks for POZZOLAN, a reaction class no
-- vanilla stone carries (A REACTION PER CONCRETE, header). RM gives it,
-- while its data is in RAM, to every inorganic flagged IGNEOUS_EXTRUSIVE
-- and to obsidian, and takes it back itself at every shutdown
-- (refinish-material-classes.lua), so this module only asks, from the
-- start hook RM runs once the module is injected.
-- Obsidian is named so it still counts if a mod clears its igneous flag;
-- the flag catches every extrusive stone, modded ones included.
-- POZZOLAN is shared vocabulary: RM's slag carries it too.
-- A stone with a legitimate class is economic, as flux is, and the
-- fort's stone settings can still mark it otherwise (accepted
-- 2026-10-03).
-- The sand grinder once graded volcanic stone by pozzolanic reactivity,
-- which tracks amorphous silica: obsidian (volcanic glass), then felsic
-- rhyolite, then intermediate andesite and dacite, then mafic basalt,
-- the floor. Every grade makes dwarven concrete; the order is kept here
-- in case grades return.
-- ==========================================
local POZZOLAN_GRANT = {
    class = 'POZZOLAN',
    inorganic_flags = { 'IGNEOUS_EXTRUSIVE' },
    ids = { 'OBSIDIAN' },
}

local function grant_pozzolan()
    local api = _G.refinish_class_api
    if not (api and api.grant) then
        -- WARNING: dwarven concrete reads red, since no dust carries
        -- POZZOLAN; the other two concretes are unaffected.
        log('WARNING', "RM's class service is not loaded, so no stone carries POZZOLAN"
            .. ' and dwarven concrete cannot be made this session.', 'POZZOLAN')
        return
    end
    local ok, n = pcall(api.grant, MODULE_ID, POZZOLAN_GRANT)
    if ok then
        log('DETAIL', ('POZZOLAN asked for: %s volcanic stone(s) given it.'):format(tostring(n)),
            'POZZOLAN')
    else
        -- ERROR: dwarven concrete reads red this session.
        log('ERROR', 'POZZOLAN could not be given: ' .. tostring(n), 'POZZOLAN')
    end
end

-- ==========================================
-- REGISTRATION
-- ==========================================
-- Connects to RM's module engine and registers a listener
-- that fires when RM broadcasts its startup token call.
-- The listener loads the JSONs, runs value calculation if needed,
-- and returns pre-built data tables to the engine, with the start hook
-- for RM to run (LIFECYCLE, in the return).
-- ==========================================
local function register_with_rm()
    -- Locate RM's module engine. If RM isn't installed, this
    -- fails gracefully: the module just doesn't register.
    local ok, engine = pcall(dfhack.script_environment, 'refinish-module-engine')
    if not ok or not engine or not engine.register_listener then
        return
    end

    engine.register_listener(MODULE_NAME, function()
        -- Resolve our mod's root folder at runtime.
        local mod_path = scriptmanager.getModSourcePath(MODULE_ID)
        if not mod_path then
            log('ERROR', "Cannot resolve the mod path for ID '" .. MODULE_ID
                .. "'.", 'DATA')
            return nil
        end

        local data_path = mod_path .. "data/"
        log('DETAIL', 'Loading from ' .. data_path, 'DATA')

        -- ---- LOAD JSON DATA ----
        local mat_data = nil
        local rxn_data = nil

        if MATERIALS_FILE then
            mat_data = load_json(data_path .. MATERIALS_FILE)
            if not mat_data then
                log('ERROR', 'Failed to load ' .. MATERIALS_FILE .. '.', 'DATA')
                return nil
            end
        end

        if REACTIONS_FILE then
            rxn_data = load_json(data_path .. REACTIONS_FILE)
            if not rxn_data then
                log('ERROR', 'Failed to load ' .. REACTIONS_FILE .. '.', 'DATA')
                return nil
            end
        end

        -- The cement form. Every mix and grind names it, so without it
        -- the module's reactions are left out by the engine; say so here
        -- first, where the cause is plain.
        local tool_data = nil
        if TOOLS_FILE then
            tool_data = load_json(data_path .. TOOLS_FILE)
            if not tool_data then
                log('ERROR', 'Failed to load ' .. TOOLS_FILE .. '.', 'DATA')
                return nil
            end
        end
        if not mat_data and not rxn_data then
            log('ERROR', 'No data files loaded, so there is nothing to inject.',
                'DATA')
            return nil
        end

        log('DETAIL', 'Data loaded successfully.', 'DATA')

        -- ---- WEIGHTED VALUE CALCULATION ----
        if mat_data and rxn_data then
            local has_null_values = false
            for _, mat in ipairs(mat_data.materials) do
                if mat.value == nil then
                    has_null_values = true
                    break
                end
            end

            if has_null_values then
                local rxn_lookup = {}
                for _, rxn in ipairs(rxn_data.reactions) do
                    rxn_lookup[rxn.key] = rxn
                end

                for _, mat in ipairs(mat_data.materials) do
                    if mat.value == nil then
                        if mat.value_from_reaction then
                            local rxn = rxn_lookup[mat.value_from_reaction]
                            if rxn and rxn.reagents then
                                mat.value = calculate_weighted_value(rxn.reagents)
                            end
                        end
                        if mat.value == nil then
                            mat.value = 1
                        end
                    end
                end
            end
        end

        -- ---- RETURN TO ENGINE ----
        -- POZZOLAN is asked for through the start hook below, not here:
        -- this token call runs before RM validates the data, and anything
        -- started here ran on for a rejected module (refinish-module-
        -- engine, MODULE LIFECYCLE).
        return {
            materials  = mat_data and mat_data.materials or nil,
            reactions  = rxn_data and rxn_data.reactions or nil,
            categories = rxn_data and rxn_data.categories or nil,
            tools      = tool_data and tool_data.tools or nil,
            module     = mat_data and mat_data.module or
                         rxn_data and rxn_data.module or nil,

            -- ---- LIFECYCLE, RUN BY RM ----
            -- start runs once the module is accepted and injected, every
            -- data cycle, so POZZOLAN is asked for again after each one.
            -- No stop: RM takes every class it gave back by itself, before
            -- any save (refinish-material-classes.lua).
            start = grant_pozzolan,
        }
    end, MODULE_ID)
end


-- ==========================================
-- SHUTDOWN
-- ==========================================
-- No map unload hook of its own any more: nothing of this module runs
-- after RM's data goes (the mix watcher retired 2026-10-03, and RM takes
-- back the class it gave). Cleared, so a hook left by an earlier version
-- of this file does nothing. (1.x stopped the sand button injector and
-- the sand multiplier here too.)
-- ==========================================
dfhack.onStateChange.making_concrete_unload = nil

-- ==========================================
-- AUTO-REGISTER ON LOAD
-- ==========================================
register_with_rm()

return _ENV