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
    -- M6 BALANCE: a brand-new player starts with 3 unlocked pads -- the starter + TWO quick free
    -- purchases, so the "buy -> number goes up" loop hooks in the first minute. Kept BELOW
    -- PadsPerPlot so the M5 "Extra Pads" gamepass (+2) and pad-unlock products still have real
    -- headroom to unlock up to the physical cap. The placement check is min(unlocked, PadsPerPlot).
    DefaultUnlockedPads = 3,
    Spacing = 64, -- studs between plot centers
    PadSpacing = 8, -- studs between pads inside one plot
    TemplateName = "PlotTemplate", -- Model name to look for in ServerStorage/Assets
}

return Config
