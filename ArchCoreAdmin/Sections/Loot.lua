-- Onglet Butin : simulateur de farm et de butin, par la commande /simloot d'ArchCore
-- (/simloot <TID du monstre> <nombre> [taux de butin] [taux d'or]). Le serveur tire le butin de
-- chaque monstre exactement comme à sa mort, sans rien créer, et répond par un en-tête puis une
-- ligne « · quantité × nom (TID n) » par objet (lues dans Replies.lua : ACA.sim).
-- À droite, deux vues : la liste des monstres à choisir (recherche par nom ou TID) et le résultat.
local addonName, ns = ...
local ACA = LibStub("AceAddon-3.0"):GetAddon("ArchCoreAdmin")
local L = LibStub("AceLocale-3.0"):GetLocale("ArchCoreAdmin")
local W = ns.W

local LIST_X, LIST_W, ROWS, MONSTER_ROWS = 316, 340, 12, 10
local QUICK = { 100, 1000, 10000 }

-- Quantité pour 100 monstres, avec une décimale au besoin.
local function per100(count, kills)
  if not kills or kills <= 0 then return "" end
  local v = count * 100 / kills
  return v >= 10 and format("%.0f", v) or format("%.1f", v)
end

ns.RegisterSection("loot", "TAB_LOOT", function(page)
  local EDIT_X = 130
  local title = W.Label(page, L["SIMLOOT"])
  title:SetPoint("TOPLEFT", page, "TOPLEFT", 0, -2)

  local function row(y, text)
    local l = W.Label(page, text, "GameFontHighlight")
    l:SetPoint("TOPLEFT", page, "TOPLEFT", 0, y - 4)
  end

  row(-28, L["MONSTER_TID"])
  local tid = W.Edit(page, 80)
  tid:SetPoint("TOPLEFT", page, "TOPLEFT", EDIT_X, -28)
  local monster = W.Label(page, "", "GameFontNormalSmall")
  monster:SetPoint("TOPLEFT", page, "TOPLEFT", EDIT_X, -54)
  monster:SetWidth(LIST_X - EDIT_X - 10)
  monster:SetWordWrap(false)
  local fromTarget = W.Button(page, L["TARGET"], 60, function()
    local t, name = ACA:TargetMonster()
    if not t then return ACA:Error(L["ERR_NO_MONSTER_TARGET"]) end
    tid:SetText(tostring(t))
    monster:SetText(name or "")
  end, L["TIP_TARGET_MONSTER"])
  fromTarget:SetPoint("LEFT", tid, "RIGHT", 6, 0)
  tid:SetScript("OnTextChanged", function(self, userInput)
    if userInput then monster:SetText(ACA:MonsterName(self:GetText()) or "") end
  end)

  row(-74, L["KILLS"])
  local kills = W.Edit(page, 80)
  kills:SetPoint("TOPLEFT", page, "TOPLEFT", EDIT_X, -74)
  kills:SetText("100")
  local x = EDIT_X
  for _, n in ipairs(QUICK) do
    local b = W.Button(page, tostring(n), 52, function() kills:SetText(tostring(n)) end)
    b:SetPoint("TOPLEFT", page, "TOPLEFT", x, -100)
    x = x + 58
  end

  -- Taux : vides, ceux du serveur (rappelés à côté, lus par /GetDrop et /GetGold).
  local server = {}
  local function rateRow(y, text, key)
    row(y, text)
    local e = W.Edit(page, 60)
    e:SetPoint("TOPLEFT", page, "TOPLEFT", EDIT_X, y)
    W.Tooltip(e, text, L["TIP_SIM_RATE"])
    local v = W.Label(page, "", "GameFontDisableSmall")
    v:SetPoint("LEFT", e, "RIGHT", 6, 0)
    v:SetWidth(LIST_X - EDIT_X - 72)
    server[key] = v
    return e
  end
  local drop = rateRow(-132, L["DROP_RATE"], "drop")
  local gold = rateRow(-160, L["GOLD_RATE"], "gold")
  local function showRates()
    for key, fs in pairs(server) do
      local v = ACA.rates[key]
      fs:SetText(format(L["SERVER_RATE"], v and format("%g", v) or "?"))
    end
  end

  local results, summary, setView
  local simulate = W.Button(page, L["SIMULATE"], 150, function()
    local d, g = strtrim(drop:GetText() or ""), strtrim(gold:GetText() or "")
    -- Arguments positionnels : un taux d'or seul demande aussi le taux de butin.
    if d == "" and g ~= "" then
      if not ACA.rates.drop then return ACA:Error(L["ERR_SIM_DROP"]) end
      d = format("%g", ACA.rates.drop)
    end
    if ACA:Run("simloot", { tid:GetText(), kills:GetText(), d, g }) then
      ACA.sim = nil
      results:Reset({})
      summary:SetText(L["SIM_WAITING"])
      setView("results")
    end
  end, L["TIP_SIMULATE"], "simloot")
  simulate:SetPoint("TOPLEFT", page, "TOPLEFT", 0, -194)
  local read = W.Button(page, L["READ_RATES"], 140, function()
    ACA:Run("GetDrop")
    ACA:Run("GetGold")
  end, L["TIP_READ_RATES"], "GetDrop")
  read:SetPoint("LEFT", simulate, "RIGHT", 6, 0)

  summary = W.Label(page, "", "GameFontHighlightSmall")
  summary:SetPoint("TOPLEFT", page, "TOPLEFT", 0, -230)
  summary:SetWidth(LIST_X - 14)
  summary:SetWordWrap(true)
  local note = W.Label(page, L["LOOT_NOTE"], "GameFontDisableSmall")
  note:SetPoint("TOPLEFT", page, "TOPLEFT", 0, -306)
  note:SetWidth(LIST_X - 14)
  note:SetWordWrap(true)

  -- Issue de /simloot quand elle n'est pas un résultat : refus expliqué, ou silence du serveur.
  ACA.resultHandlers.simloot = function(kind, text)
    if kind == "ok" then return end
    local message
    if kind == "timeout" then
      message = L["SIM_NO_REPLY"]
    elseif text:find("^monstre inconnu") then
      message = format(L["SIM_UNKNOWN_MONSTER"], tid:GetText() or "")
    else
      message = format(L["REFUSED_OTHER"], text)
    end
    ACA:Error(message)
    summary:SetText("|cffff6060" .. message .. "|r")
  end

  -- Vue « Monstres » : la liste vient du client s'il la donne, sinon des monstres déjà rencontrés.
  local viewButtons, monsterFrames, resultFrames = {}, {}, {}
  local monsterSearch = W.Edit(page, 180)
  monsterSearch:SetPoint("TOPLEFT", page, "TOPLEFT", LIST_X, -26)
  W.Tooltip(monsterSearch, L["SEARCH"], L["TIP_SEARCH_MONSTER"])
  local monsterCount = W.Label(page, "", "GameFontDisableSmall")
  monsterCount:SetPoint("TOPLEFT", page, "TOPLEFT", LIST_X + 188, -30)
  monsterCount:SetWidth(LIST_W - 188)
  monsterCount:SetWordWrap(false)
  local monsters = W.ItemList(page, LIST_W, MONSTER_ROWS, {
    { width = 44, text = function(m) return tostring(m.tid) end },
    { width = 30, text = function(m) return m.level and m.level > 0 and tostring(m.level) or "" end },
  }, function(m)
    tid:SetText(tostring(m.tid))
    monster:SetText(m.name)
  end, nil, {
    noIcon = true,
    tooltip = function(owner, m)
      GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
      GameTooltip:SetText(m.name)
      GameTooltip:AddLine(format(L["ITEM_TIP_TID"], m.tid), 0.7, 0.7, 0.7)
      if m.level and m.level > 0 then GameTooltip:AddLine(format(L["MONSTER_TIP_LEVEL"], m.level), 1, 1, 1) end
      if m.inView then GameTooltip:AddLine(L["MONSTER_TIP_IN_VIEW"], 0.6, 0.8, 1) end
      GameTooltip:Show()
    end,
  })
  monsters:SetPoint("TOPLEFT", page, "TOPLEFT", LIST_X, -64)
  local headName = W.Label(page, L["MONSTER"], "GameFontDisableSmall")
  headName:SetPoint("BOTTOMLEFT", monsters, "TOPLEFT", 8, 2)
  local headTid = W.Label(page, "TID", "GameFontDisableSmall")
  headTid:SetPoint("BOTTOMRIGHT", monsters, "TOPRIGHT", -44, 2)
  headTid:SetJustifyH("RIGHT")
  local headLevel = W.Label(page, L["LEVEL_SHORT"], "GameFontDisableSmall")
  headLevel:SetPoint("BOTTOMRIGHT", monsters, "TOPRIGHT", -8, 2)
  headLevel:SetJustifyH("RIGHT")
  local monsterNote = W.Label(page, "", "GameFontDisableSmall")
  monsterNote:SetPoint("TOPLEFT", page, "TOPLEFT", LIST_X, -336)
  monsterNote:SetWidth(LIST_W)
  monsterNote:SetWordWrap(true)
  monsterFrames = { monsterSearch, monsterCount, monsters, headName, headTid, headLevel, monsterNote }

  local function refreshMonsters()
    local found = ACA:SearchMonsters(monsterSearch:GetText())
    monsters:SetItems(found)
    monsterCount:SetText(format(L["MONSTERS_COUNT"], #found))
    monsterNote:SetText(ACA:MonsterTemplates() and L["MONSTERS_NOTE_SERVER"] or L["MONSTERS_NOTE_SEEN"])
  end
  monsterSearch:SetScript("OnTextChanged", function()
    monsters:Reset({})
    refreshMonsters()
  end)

  -- Résultat : objets obtenus, du plus fréquent au plus rare, avec leur icône.
  local head = W.Label(page, L["SIM_RESULTS"], "GameFontDisableSmall")
  head:SetPoint("TOPLEFT", page, "TOPLEFT", LIST_X + 34, -28)
  local headCount = W.Label(page, L["COUNT_SHORT"], "GameFontDisableSmall")
  headCount:SetPoint("TOPRIGHT", page, "TOPLEFT", LIST_X + LIST_W - 70, -28)
  headCount:SetJustifyH("RIGHT")
  local headRate = W.Label(page, L["PER_100"], "GameFontDisableSmall")
  headRate:SetPoint("TOPRIGHT", page, "TOPLEFT", LIST_X + LIST_W - 8, -28)
  headRate:SetJustifyH("RIGHT")
  results = W.ItemList(page, LIST_W, ROWS, {
    { width = 56, text = function(item) return tostring(item.count) end },
    { width = 56, text = function(item) return per100(item.count, ACA.sim and ACA.sim.kills) end },
  }, nil, function(item)
    local k = ACA.sim and ACA.sim.kills
    return { format(L["TIP_SIM_COUNT"], item.count, k or 0, per100(item.count, k)) }
  end)
  results:SetPoint("TOPLEFT", page, "TOPLEFT", LIST_X, -42)
  resultFrames = { head, headCount, headRate, results }

  -- Bascule entre les deux vues de droite.
  function setView(view)
    page.view = view
    for _, f in ipairs(monsterFrames) do f:SetShown(view == "monsters") end
    for _, f in ipairs(resultFrames) do f:SetShown(view == "results") end
    for v, b in pairs(viewButtons) do
      if v == view then b:Disable() else b:Enable() end
    end
    if view == "monsters" then refreshMonsters() end
  end
  local step = math.floor((LIST_W + 6) / 2)
  viewButtons.monsters = W.Button(page, L["MONSTERS"], step - 6, function() setView("monsters") end)
  viewButtons.monsters:SetPoint("TOPLEFT", page, "TOPLEFT", LIST_X, 0)
  viewButtons.results = W.Button(page, L["SIM_RESULTS"], step - 6, function() setView("results") end)
  viewButtons.results:SetPoint("TOPLEFT", page, "TOPLEFT", LIST_X + step, 0)

  local function showSim()
    local s = ACA.sim
    if not s then return end
    results:SetItems(s.items)
    if s.monster then monster:SetText(s.monster) end
    local lines = {
      format(L["SIM_HEADER"], s.kills, s.monster, s.tid, s.level),
      format(L["SIM_PARAMS"], format("%g", s.drop), format("%g", s.goldRate), s.killer),
      format(L["SIM_GOLD"], s.gold),
      format(L["SIM_TOTAL"], s.total, s.kinds),
    }
    if s.more then lines[#lines + 1] = format(L["SIM_MORE"], s.more.kinds, s.more.count) end
    summary:SetText(table.concat(lines, "\n"))
  end
  ACA:RegisterMessage("ARCHCOREADMIN_SIM", showSim)
  ACA:RegisterMessage("ARCHCOREADMIN_RATES", showRates)
  -- Un monstre vient d'être rencontré : la liste se met à jour si elle est à l'écran.
  ACA:RegisterMessage("ARCHCOREADMIN_MONSTERS", function()
    if page:IsVisible() and page.view == "monsters" then refreshMonsters() end
  end)
  function page:OnShow()
    showRates()
    showSim()
    setView(page.view or (ACA.sim and "results" or "monsters"))
  end
  page.tid, page.kills, page.drop, page.gold, page.results, page.summary = tid, kills, drop, gold, results, summary
  page.monsters, page.monsterSearch, page.monsterName, page.viewButtons = monsters, monsterSearch, monster, viewButtons
end)
