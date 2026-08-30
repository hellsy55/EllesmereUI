if EUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (EllesmereUI_ClientGate.lua)
--------------------------------------------------------------------------------
--  EllesmereUI_NumberFormat.lua
--  Central "abbreviate a big number to K/M/B/etc." engine, shared by every module
--  that squeezes a large number into a small space (Gold in EllesmereUIDataBars,
--  damage/healing in EllesmereUIDamageMeters, ...). Delegates to the client's own
--  AbbreviateNumbers/CreateAbbreviateConfig -- guaranteed present on every client
--  build this addon supports (EUI_CLIENT_BLOCKED gates out anything older, and
--  both APIs predate that floor by years); this file only supplies the
--  breakpoint table.
--
--  Locale-specific algorithms (CJK 万/亿-style grouping) do NOT live here -- they
--  are registered from inside the matching EllesmereUILocales/<code>.lua file via
--  RegisterNumberAbbreviation below, so the algorithm and its glyphs travel
--  together with the LoadOnDemand child that already never loads at all for an
--  English client (see EllesmereUI_Locale.lua's "Zero cost on English" note).
--
--  AbbreviateNumber() runs on every combat-meter and gold-bar refresh, often many
--  times a second across a raid frame's worth of bars, so it's written as a hot
--  path: client API localized to upvalues, and the resolved AbbreviateConfig built
--  at most once per session (EllesmereUI.LOCALE cannot change without a UI reload,
--  per EUI__General_Options.lua's language picker, so there is nothing to
--  invalidate).
--------------------------------------------------------------------------------
EllesmereUI = EllesmereUI or {}
local EllesmereUI = EllesmereUI

local tonumber = tonumber
local AbbreviateNumbers = AbbreviateNumbers
local CreateAbbreviateConfig = CreateAbbreviateConfig

-- English/default breakpoint table -- there's no locale-agnostic "generic"
-- abbreviation, K/M/B is just what English (and every locale without its own
-- registration below) uses. One table fits every caller: an unreached
-- breakpoint (e.g. the B tier on gold, capped at 99,999,999) simply never
-- matches, so there's no need for a caller-specific variant.
local function EnglishBreakpoints()
    return {
        { breakpoint = 1000000000, abbreviation = "B", significandDivisor = 10000000, fractionDivisor = 100, abbreviationIsGlobal = false },
        { breakpoint = 1000000,    abbreviation = "M", significandDivisor = 10000,    fractionDivisor = 100, abbreviationIsGlobal = false },
        { breakpoint = 1000,       abbreviation = "K", significandDivisor = 100,      fractionDivisor = 10,  abbreviationIsGlobal = false },
        { breakpoint = 1,          abbreviation = "",  significandDivisor = 1,        fractionDivisor = 1,   abbreviationIsGlobal = false },
    }
end

-- Locale-specific overrides: [localeCode] -> breakpoint-table builder.
-- Populated by EllesmereUILocales/<code>.lua files at their own load (only the
-- active locale's file actually runs on a given client).
local localeBuilders = {}

function EllesmereUI.RegisterNumberAbbreviation(localeCode, builderFn)
    localeBuilders[localeCode] = builderFn
end

-- EllesmereUI.LocaleHasNumberAbbreviation(localeCode) -> boolean
--   True when localeCode (default: the current effective locale) has its own
--   registered algorithm -- i.e. a "Force English Units" toggle would actually
--   change something for it. Lets callers (options pages) gate that toggle
--   without hardcoding which locales happen to have one.
function EllesmereUI.LocaleHasNumberAbbreviation(localeCode)
    localeCode = localeCode or EllesmereUI.LOCALE
    return localeBuilders[localeCode] ~= nil
end

-- Resolved AbbreviateConfig objects, built at most once and reused for the rest
-- of the session -- plain upvalues rather than a table keyed by locale, so a
-- warm call is a truthiness check away from returning instead of a hash lookup.
local cfgLocalized, cfgEnglish

local function BuildConfig(forceEnglish)
    if forceEnglish then
        cfgEnglish = cfgEnglish or { config = CreateAbbreviateConfig(EnglishBreakpoints()) }
        return cfgEnglish
    end
    if not cfgLocalized then
        local builder = localeBuilders[EllesmereUI.LOCALE]
        local opts = builder and builder() or EnglishBreakpoints()
        cfgLocalized = { config = CreateAbbreviateConfig(opts) }
    end
    return cfgLocalized
end

-- EllesmereUI.AbbreviateNumber(n, forceEnglish) -> string
--   forceEnglish: true skips any locale-specific override and always uses
--   K/M/B (e.g. DamageMeters' "force English units" setting).
function EllesmereUI.AbbreviateNumber(n, forceEnglish)
    return AbbreviateNumbers(tonumber(n) or 0, BuildConfig(forceEnglish))
end
