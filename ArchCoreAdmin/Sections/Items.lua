-- Onglet Objets (la recherche d'objets d'AzerothAdmin) : /create "nom" <TID> <quantité> <0|1>.
-- ArchCore n'a pas de commande de recherche : les objets se désignent par leur TID. L'AddOn
-- apprend le nom de chaque objet dans la réponse du serveur (« 5 × Potion (TID 190) donné(s) ») et
-- garde une liste de favoris.
local addonName, ns = ...
local ACA = LibStub("AceAddon-3.0"):GetAddon("ArchCoreAdmin")
local L = LibStub("AceLocale-3.0"):GetLocale("ArchCoreAdmin")
local W = ns.W

local function itemName(tid)
  return tid and ACA.db.global.itemNames[tid]
end

ns.RegisterSection("items", "TAB_ITEMS", function(page)
  local favorites = ACA.db.global.items
  local X = 250

  local list = W.List(page, 236, 18, function(item)
    page.tid:SetText(tostring(item.tid))
    page.label:SetText(item.name or "")
  end)
  list:SetPoint("TOPLEFT", page, "TOPLEFT", 0, -18)
  local title = W.Label(page, L["FAVORITES"])
  title:SetPoint("BOTTOMLEFT", list, "TOPLEFT", 2, 3)
  local function refresh()
    table.sort(favorites, function(a, b) return a.tid < b.tid end)
    list:SetItems(favorites, function(item)
      return format("%d  %s", item.tid, item.name or itemName(item.tid) or "?")
    end)
  end

  local function row(y, text)
    local l = W.Label(page, text, "GameFontHighlight")
    l:SetPoint("TOPLEFT", page, "TOPLEFT", X, y - 4)
  end

  row(-18, L["RECIPIENT"])
  local recipient = W.Edit(page, 150)
  recipient:SetPoint("TOPLEFT", page, "TOPLEFT", X + 100, -18)
  local fromTarget = W.Button(page, L["TARGET"], 70, function()
    local t = ACA:TargetPlayerName()
    if t then recipient:SetText(t) else ACA:Error(L["ERR_NO_PLAYER_TARGET"]) end
  end, L["TIP_TARGET"])
  fromTarget:SetPoint("LEFT", recipient, "RIGHT", 6, 0)
  local me = W.Button(page, L["SELF"], 54, function() recipient:SetText(UnitName("player") or "") end)
  me:SetPoint("LEFT", fromTarget, "RIGHT", 6, 0)

  row(-50, L["TID"])
  page.tid = W.Edit(page, 90)
  page.tid:SetPoint("TOPLEFT", page, "TOPLEFT", X + 100, -50)
  local known = W.Label(page, "", "GameFontNormalSmall")
  known:SetPoint("LEFT", page.tid, "RIGHT", 8, 0)
  known:SetWidth(200)
  page.tid:SetScript("OnTextChanged", function(self)
    local name = itemName(tonumber(self:GetText()))
    known:SetText(name or "")
  end)

  row(-82, L["QUANTITY"])
  local qty = W.Edit(page, 60)
  qty:SetPoint("TOPLEFT", page, "TOPLEFT", X + 100, -82)
  qty:SetText("1")
  local bound = W.Check(page, L["NOT_TRADABLE"], function() end)
  bound:SetPoint("LEFT", qty, "RIGHT", 14, 0)

  local create = W.Button(page, L["CREATE"], 150, function()
    local who = strtrim(recipient:GetText() or "")
    if who == "" then who = UnitName("player") or "" end
    ACA:Run("create", { who, page.tid:GetText(), qty:GetText(), bound:GetChecked() and 1 or 0 })
  end, L["TIP_CREATE"], "create")
  create:SetPoint("TOPLEFT", page, "TOPLEFT", X + 100, -116)

  row(-162, L["FAVORITE_NAME"])
  page.label = W.Edit(page, 170)
  page.label:SetPoint("TOPLEFT", page, "TOPLEFT", X + 100, -162)
  local add = W.Button(page, L["ADD_FAVORITE"], 130, function()
    local tid = tonumber(page.tid:GetText())
    if not tid then return ACA:Error(format(L["ERR_INT"], page.tid:GetText() or "")) end
    local label = strtrim(page.label:GetText() or "")
    if label == "" then label = itemName(tid) end
    for _, item in ipairs(favorites) do
      if item.tid == tid then
        item.name = label
        return refresh()
      end
    end
    tinsert(favorites, { tid = tid, name = label })
    refresh()
  end)
  add:SetPoint("TOPLEFT", page, "TOPLEFT", X + 100, -194)
  local remove = W.Button(page, L["REMOVE"], 100, function()
    local item = list.selected and favorites[list.selected]
    if not item then return end
    tremove(favorites, list.selected)
    list.selected = nil
    refresh()
  end)
  remove:SetPoint("LEFT", add, "RIGHT", 6, 0)

  local note = W.Label(page, L["ITEMS_NOTE"], "GameFontDisableSmall")
  note:SetPoint("TOPLEFT", page, "TOPLEFT", X, -236)
  note:SetWidth(400)
  note:SetWordWrap(true)

  ACA:RegisterMessage("ARCHCOREADMIN_ITEMS", function()
    refresh()
    page.tid:GetScript("OnTextChanged")(page.tid)
  end)
  function page:OnShow()
    if strtrim(recipient:GetText() or "") == "" then recipient:SetText(UnitName("player") or "") end
    refresh()
  end
end)
