-- Onglet Joueurs (l'onglet « Char » d'AzerothAdmin) : un nom (saisi, ciblé ou choisi parmi les
-- joueurs en vue) et les commandes qui s'y appliquent : /kill, /level, /money, /rename_char,
-- /chatban. Sans nom, /kill, /level et /money s'appliquent au MJ lui-même.
local addonName, ns = ...
local ACA = LibStub("AceAddon-3.0"):GetAddon("ArchCoreAdmin")
local L = LibStub("AceLocale-3.0"):GetLocale("ArchCoreAdmin")
local W = ns.W

ns.RegisterSection("players", "TAB_PLAYERS", function(page)
  local list = W.List(page, 170, 18, function(name) page.name:SetText(name) end)
  list:SetPoint("TOPLEFT", page, "TOPLEFT", 0, -18)
  local title = W.Label(page, L["PLAYERS_IN_VIEW"])
  title:SetPoint("BOTTOMLEFT", list, "TOPLEFT", 2, 3)
  local function refreshList() list:SetItems(ACA:PlayersInView()) end
  local refresh = W.Button(page, L["REFRESH"], 170, refreshList)
  refresh:SetPoint("TOPLEFT", list, "BOTTOMLEFT", 0, -4)

  local X = 190
  local function row(y, text)
    local l = W.Label(page, text, "GameFontHighlight")
    l:SetPoint("TOPLEFT", page, "TOPLEFT", X, y - 4)
    return l
  end
  local function name() return strtrim(page.name:GetText() or "") end

  row(-18, L["NAME"])
  page.name = W.Edit(page, 170)
  page.name:SetPoint("TOPLEFT", page, "TOPLEFT", X + 110, -18)
  local fromTarget = W.Button(page, L["TARGET"], 80, function()
    local t = ACA:TargetPlayerName()
    if t then page.name:SetText(t) else ACA:Error(L["ERR_NO_PLAYER_TARGET"]) end
  end, L["TIP_TARGET"])
  fromTarget:SetPoint("LEFT", page.name, "RIGHT", 6, 0)
  local me = W.Button(page, L["SELF"], 60, function() page.name:SetText("") end, L["TIP_SELF"])
  me:SetPoint("LEFT", fromTarget, "RIGHT", 6, 0)

  local kill = W.Button(page, L["KILL"], 120, function() ACA:Run("kill", { name() }) end, L["TIP_KILL"], "kill")
  kill:SetPoint("TOPLEFT", page, "TOPLEFT", X + 110, -52)

  row(-86, L["LEVEL"])
  local level = W.Edit(page, 60)
  level:SetPoint("TOPLEFT", page, "TOPLEFT", X + 110, -86)
  local setLevel = W.Button(page, L["SET_LEVEL"], 120, function()
    ACA:Run("level", { level:GetText(), name() })
  end, L["TIP_LEVEL_CMD"], "level")
  setLevel:SetPoint("LEFT", level, "RIGHT", 6, 0)

  row(-118, L["GOLD"])
  local gold = W.Edit(page, 110)
  gold:SetPoint("TOPLEFT", page, "TOPLEFT", X + 110, -118)
  local setGold = W.Button(page, L["SET_GOLD"], 120, function()
    ACA:Run("money", { gold:GetText(), name() })
  end, L["TIP_MONEY"], "money")
  setGold:SetPoint("LEFT", gold, "RIGHT", 6, 0)

  row(-150, L["NEW_NAME"])
  local newName = W.Edit(page, 140)
  newName:SetPoint("TOPLEFT", page, "TOPLEFT", X + 110, -150)
  local rename = W.Button(page, L["RENAME"], 120, function()
    ACA:Run("rename_char", { name(), newName:GetText() })
  end, L["TIP_RENAME"], "rename_char")
  rename:SetPoint("LEFT", newName, "RIGHT", 6, 0)

  -- Silence : durées prédéfinies, durée libre en minutes, ou 0 pour lever.
  row(-190, L["CHATBAN"])
  local minutes = W.Edit(page, 60)
  minutes:SetPoint("TOPLEFT", page, "TOPLEFT", X + 110, -190)
  local apply = W.Button(page, L["APPLY"], 90, function()
    ACA:Run("chatban", { name(), minutes:GetText() })
  end, L["TIP_CHATBAN"], "chatban")
  apply:SetPoint("LEFT", minutes, "RIGHT", 6, 0)
  local lift = W.Button(page, L["LIFT"], 90, function()
    ACA:Run("chatban", { name(), 0 })
  end, L["TIP_UNBAN"], "chatban")
  lift:SetPoint("LEFT", apply, "RIGHT", 6, 0)
  local x = X + 110
  for _, d in ipairs({ { 5, "5 min" }, { 15, "15 min" }, { 60, "1 h" }, { 1440, L["ONE_DAY"] } }) do
    local b = W.Button(page, d[2], 66, function()
      minutes:SetText(tostring(d[1]))
      ACA:Run("chatban", { name(), d[1] })
    end, format(L["TIP_CHATBAN_FOR"], d[2]), "chatban")
    b:SetPoint("TOPLEFT", page, "TOPLEFT", x, -220)
    x = x + 72
  end

  local note = W.Label(page, L["PLAYERS_NOTE"], "GameFontDisableSmall")
  note:SetPoint("TOPLEFT", page, "TOPLEFT", X, -262)
  note:SetWidth(460)
  note:SetWordWrap(true)

  -- Liste des joueurs en vue rafraîchie toutes les 2 s tant que l'onglet est affiché.
  local acc = 0
  page:SetScript("OnUpdate", function(_, elapsed)
    acc = acc + elapsed
    if acc >= 2 then
      acc = 0
      refreshList()
    end
  end)
  function page:OnShow() refreshList() end
end)
