-- Onglet Journal (l'onglet « Log » d'AzerothAdmin) : commandes envoyées et réponses du serveur,
-- horodatées, gardées par personnage (300 lignes au plus).
local addonName, ns = ...
local ACA = LibStub("AceAddon-3.0"):GetAddon("ArchCoreAdmin")
local L = LibStub("AceLocale-3.0"):GetLocale("ArchCoreAdmin")
local W = ns.W

local COLORS = { [">"] = "|cffffd200", ["<"] = "|cffffffff", ["!"] = "|cffff5050" }

local function line(e)
  return format("|cff888888%s|r %s%s %s|r", date("%H:%M:%S", e.t), COLORS[e.k] or "", e.k, e.s)
end

ns.RegisterSection("log", "TAB_LOG", function(page)
  local list = W.List(page, 656, 19, function(e) ACA:Print(e.s) end)
  list:SetPoint("TOPLEFT", page, "TOPLEFT", 0, 0)

  local function refresh()
    list:SetItems(ACA.db.char.log, line)
    list:ScrollToEnd()
  end
  local clear = W.Button(page, L["CLEAR"], 110, function()
    wipe(ACA.db.char.log)
    refresh()
  end)
  clear:SetPoint("TOPLEFT", list, "BOTTOMLEFT", 0, -6)
  local hint = W.Label(page, L["LOG_HINT"], "GameFontDisableSmall")
  hint:SetPoint("LEFT", clear, "RIGHT", 12, 0)

  ACA:RegisterMessage("ARCHCOREADMIN_LOG", function()
    if page:IsVisible() then refresh() end
  end)
  page.OnShow = refresh
end)
