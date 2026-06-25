-- Shared world/plot tuning. Procedural plots are generated from these numbers; a real
-- plot Model in ServerStorage/Assets (named TemplateName) overrides them later.
--
-- NOTE: brainrot stats (including the free starter) now live in Shared/Catalog -- the
-- full data-driven roster. The starter is derived from the roster as the cheapest Common
-- (Catalog.GetStarter), so there is nothing brainrot-specific to tune in this file.

local Config = {}

Config.Plots = {
    Count = 6, -- how many bases to create in the world
    PadsPerPlot = 5, -- PHYSICAL brainrot stands built per base (the hard cap on placed units)
    -- VM-fix: every PHYSICAL pad is usable out of the box. Previously this was 3 while 5 pads were
    -- built, so players saw empty pads they couldn't use ("No free pads") -- and because the
    -- "Extra Pads" gamepass / "Instant Pad" product Ids are still 0 (placeholder), a PUBLISHED
    -- player had no way to unlock the rest and was hard-capped at 3. Setting this to PadsPerPlot
    -- makes all built pads usable. (To sell MORE pads later, raise PadsPerPlot above this and widen
    -- the base; the Extra Pads/Instant Pad benefits already add on top via min(unlocked, PadsPerPlot).)
    DefaultUnlockedPads = 5,
    Spacing = 64, -- studs between plot centers
    PadSpacing = 8, -- studs between pads inside one plot
    TemplateName = "PlotTemplate", -- Model name to look for in ServerStorage/Assets
}

return Config
