-- Onglet MJ (l'onglet « Main » d'AzerothAdmin) : niveau MJ détecté, commandes qui portent sur le
-- MJ lui-même (/invincible, /speed, /recast, /questreset), commande libre avec historique, catalogue de
-- toutes les commandes, et réglages de l'AddOn.
local addonName, ns = ...
local ACA = LibStub("AceAddon-3.0"):GetAddon("ArchCoreAdmin")
local L = LibStub("AceLocale-3.0"):GetLocale("ArchCoreAdmin")
local W = ns.W

ns.RegisterSection("gm", "TAB_GM", function(page)
  local p = ACA.db.profile

  -- Colonne de gauche : soi-même et réglages
  local level = W.Label(page, "", "GameFontNormalLarge")
  level:SetPoint("TOPLEFT", page, "TOPLEFT", 0, -6)
  local probe = W.Button(page, L["PROBE"], 130, function() ACA:ProbeLevel() end, L["TIP_PROBE"])
  probe:SetPoint("TOPLEFT", page, "TOPLEFT", 0, -30)

  local l = W.Label(page, L["INVINCIBLE"], "GameFontHighlight")
  l:SetPoint("TOPLEFT", page, "TOPLEFT", 0, -64)
  local state = W.Label(page, "", "GameFontNormalSmall")
  state:SetPoint("LEFT", l, "RIGHT", 8, 0)
  local on = W.Button(page, L["ENABLE"], 96, function() ACA:Run("invincible", { 1 }) end, L["TIP_INVINCIBLE"], "invincible")
  on:SetPoint("TOPLEFT", page, "TOPLEFT", 0, -82)
  local off = W.Button(page, L["DISABLE"], 96, function() ACA:Run("invincible", { 0 }) end, nil, "invincible")
  off:SetPoint("LEFT", on, "RIGHT", 6, 0)

  -- Vitesse : multiplicateur de 1 à 10 (/speed), oublié par le serveur à la déconnexion.
  l = W.Label(page, L["SPEED"], "GameFontHighlight")
  l:SetPoint("TOPLEFT", page, "TOPLEFT", 0, -120)
  local speed = W.Edit(page, 36)
  speed:SetPoint("TOPLEFT", page, "TOPLEFT", 90, -116)
  local setSpeed = W.Button(page, L["SET"], 70, function()
    ACA:Run("speed", { speed:GetText() })
  end, L["TIP_SPEED"], "speed")
  setSpeed:SetPoint("LEFT", speed, "RIGHT", 6, 0)
  local speedState = W.Label(page, "", "GameFontNormalSmall")
  speedState:SetPoint("LEFT", setSpeed, "RIGHT", 6, 0)
  local x = 0
  for _, n in ipairs({ 1, 2, 3, 5, 10 }) do
    local b = W.Button(page, "×" .. n, 44, function()
      speed:SetText(tostring(n))
      ACA:Run("speed", { n })
    end, n == 1 and L["TIP_SPEED_RESET"] or format(L["TIP_SPEED_TIMES"], n), "speed")
    b:SetPoint("TOPLEFT", page, "TOPLEFT", x, -142)
    x = x + 49
  end

  local recast = W.Button(page, L["RECAST"], 198, function() ACA:Run("recast") end, L["TIP_RECAST"], "recast")
  recast:SetPoint("TOPLEFT", page, "TOPLEFT", 0, -176)

  l = W.Label(page, L["QUEST_TID"], "GameFontHighlight")
  l:SetPoint("TOPLEFT", page, "TOPLEFT", 0, -214)
  local quest = W.Edit(page, 60)
  quest:SetPoint("TOPLEFT", page, "TOPLEFT", 90, -210)
  local reset = W.Button(page, L["QUEST_RESET"], 88, function()
    ACA:Run("questreset", { quest:GetText() })
  end, L["TIP_QUESTRESET"], "questreset")
  reset:SetPoint("LEFT", quest, "RIGHT", 6, 0)

  local options = W.Label(page, L["OPTIONS"])
  options:SetPoint("TOPLEFT", page, "TOPLEFT", 0, -246)
  local y = -264
  local function option(key, text, after)
    local cb = W.Check(page, text, function(v)
      p[key] = v and true or false
      if after then after() end
    end)
    cb:SetPoint("TOPLEFT", page, "TOPLEFT", 0, y)
    cb:SetScript("OnShow", function(self) self:SetChecked(p[key]) end)
    cb:SetChecked(p[key])
    y = y - 24
    return cb
  end
  option("confirm", L["OPT_CONFIRM"])
  option("showReplies", L["OPT_REPLIES"])
  option("probe", L["OPT_PROBE"])
  option("launcher", L["OPT_LAUNCHER"], function() ACA:UpdateLauncher() end)

  -- Colonne de droite : commande libre, historique, catalogue
  local X = 260
  l = W.Label(page, L["FREE_COMMAND"])
  l:SetPoint("TOPLEFT", page, "TOPLEFT", X, -6)
  local free = W.Edit(page, 300)
  free:SetPoint("TOPLEFT", page, "TOPLEFT", X, -24)
  local function send()
    ACA:RunFree(free:GetText())
    free:SetText("")
    page.history:SetItems(ACA.db.char.history)
  end
  free:SetScript("OnEnterPressed", function(self) self:ClearFocus() send() end)
  local go = W.Button(page, L["SEND"], 86, send, L["TIP_FREE"])
  go:SetPoint("LEFT", free, "RIGHT", 6, 0)

  l = W.Label(page, L["HISTORY"], "GameFontNormalSmall")
  l:SetPoint("TOPLEFT", page, "TOPLEFT", X, -54)
  page.history = W.List(page, 392, 6, function(line) free:SetText(line) end)
  page.history:SetPoint("TOPLEFT", page, "TOPLEFT", X, -68)

  l = W.Label(page, L["CATALOG"], "GameFontNormalSmall")
  l:SetPoint("TOPLEFT", page, "TOPLEFT", X, -180)
  local catalog = W.List(page, 392, 8, function(c) free:SetText(c.usage) end)
  catalog:SetPoint("TOPLEFT", page, "TOPLEFT", X, -194)
  local function refreshCatalog()
    local items = {}
    for _, c in ipairs(ns.Catalog) do
      if c.archcore or p.showUnsupported then items[#items + 1] = c end
    end
    catalog:SetItems(items, function(c)
      if not c.archcore then return "|cff777777" .. c.usage .. "  (" .. L["NOT_HANDLED"] .. ")|r" end
      local color = ACA:CanUse(c.name) and "|cffffffff" or "|cff996666"
      return format("%s%s|r  |cff999999MJ %d|r", color, c.usage, ACA:RequiredLevel(c.name))
    end)
  end
  local unsupported = W.Check(page, L["OPT_UNSUPPORTED"], function(v)
    p.showUnsupported = v and true or false
    refreshCatalog()
  end)
  unsupported:SetPoint("TOPLEFT", catalog, "BOTTOMLEFT", 0, -4)
  unsupported:SetChecked(p.showUnsupported)

  local function refresh()
    level:SetText(ACA:LevelText())
    state:SetText(ACA.invincible == nil and "" or (ACA.invincible and L["ON"] or L["OFF"]))
    speedState:SetText(ACA.speed and ("×" .. ACA.speed) or "")
    refreshCatalog()
  end
  ACA:RegisterMessage("ARCHCOREADMIN_LEVEL", refresh)
  ACA:RegisterMessage("ARCHCOREADMIN_STATE", refresh)
  function page:OnShow()
    page.history:SetItems(ACA.db.char.history)
    refresh()
  end
end)
