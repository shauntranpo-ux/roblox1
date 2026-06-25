-- Shared, data-driven configuration for the brainrot economy.
-- Single source of truth: future milestones add a full roster + tuning here
-- WITHOUT touching any service logic. "Skin-swappable" by design.

local Config = {}

-- The single starter brainrot for M1. Add more entries (rare, epic, ...) later;
-- services read whatever is defined here and never hardcode stats.
-- ModelName is reserved: the name of a Model in ServerStorage/Assets to clone
-- once real art exists (ignored while we spawn placeholder parts).
Config.Brainrots = {
    starter = {
        Name = "Starter Brainrot",
        IncomePerSec = 1,
        ModelName = "StarterBrainrot",
    },
}

-- The Type granted to brand-new players.
Config.StarterType = "starter"

-- Plot/world tuning. Procedural parts are generated from these numbers now;
-- a real plot Model in ServerStorage/Assets (named TemplateName) overrides them later.
Config.Plots = {
    Count = 6, -- how many bases to create in the world
    PadsPerPlot = 4, -- brainrot stands per base
    Spacing = 64, -- studs between plot centers
    PadSpacing = 8, -- studs between pads inside one plot
    TemplateName = "PlotTemplate", -- Model name to look for in ServerStorage/Assets
}

return Config
