-- Onglet Objets (la recherche d'objets d'AzerothAdmin) : /create "nom" <TID> <quantité> <0|1>,
-- et /additem <TID> [quantité] pour soi.
-- ArchCore n'a pas de commande de recherche : les objets se choisissent dans le catalogue du client
-- (ArchRust.GetItemTemplate : nom, icône, niveau requis, catégorie), par catégorie et par nom, ou se
-- désignent par leur TID. Sans ce catalogue (client plus ancien), seuls la saisie du TID et les
-- favoris restent ; le nom de l'objet est alors appris dans la réponse du serveur (« 5 × Potion de
-- vie (TID 190) donné(s) »).
-- Sous les boutons, une ligne dit ce qu'il est advenu de la commande : objet donné, refus expliqué, ou
-- silence du serveur (les refus n'arrivent pas encore aux AddOns, voir docs/BESOINS-CLIENT-SERVEUR.md).
local addonName, ns = ...
local ACA = LibStub("AceAddon-3.0"):GetAddon("ArchCoreAdmin")
local L = LibStub("AceLocale-3.0"):GetLocale("ArchCoreAdmin")
local W = ns.W

-- Catégories d'ArchRust.SearchItems (« all » : toutes), puis les favoris.
local CATEGORIES = { "all", "weapon", "armor", "jewel", "mount", "usable", "other", "favorites" }
-- Largeur de la page (fenêtre moins les marges), de la liste ; lignes de la liste.
local PAGE_W, LIST_W, ROWS = 656, 330, 10
local MAX_QUANTITY = 9999
-- Couleurs de la ligne d'état.
local GOOD, BAD, WAITING = "|cff60e060", "|cffff6060", "|cffe0c060"

-- « Nom (TID n) », ou « TID n » pour un objet sans nom connu.
local function itemLabel(tid)
  local name = ACA:ItemName(tid)
  return name and format("%s (TID %s)", name, tostring(tid)) or format("TID %s", tostring(tid))
end

-- Raison donnée par le serveur (gm.rs) → explication pour le MJ.
local function explainRefusal(reason, tid)
  if reason:find("^objet inconnu") then return format(L["REFUSED_ITEM"], itemLabel(tid)) end
  local who = reason:match("^personnage introuvable : (.+)$")
  if who then return format(L["REFUSED_CHARACTER"], who) end
  if reason:find("^inventaire plein") then return L["REFUSED_FULL"] end
  return format(L["REFUSED_OTHER"], reason)
end

-- Pas de réponse : le client ne remet pas les refus aux AddOns, seules les causes possibles sont sûres,
-- sauf si ses tables disent déjà que le serveur n'a pas cet objet.
local function explainSilence(tid)
  local t = ACA:ItemTemplate(tid)
  if t and t.server == false then return format(L["REFUSED_ITEM"], itemLabel(tid)) end
  return format(L["NO_REPLY_ITEM"], itemLabel(tid))
end

ns.RegisterSection("items", "TAB_ITEMS", function(page)
  local favorites = ACA.db.global.items
  local catalog = ACA:HasItemCatalog()
  local X, LABEL = LIST_W + 14, 100
  local category = catalog and "all" or "favorites"
  -- Classe choisie : rang dans ns.CLASSES, 0 pour toutes.
  local classIndex = 0
  local status, note, clearStatus

  -- Liste des objets, avec icône, TID et niveau requis.
  local list = W.ItemList(page, LIST_W, ROWS, {
    { width = 44, text = function(item) return tostring(item.tid) end },
    { width = 30, text = function(item)
      local level = item.level
      if level == nil then
        local t = ACA:ItemTemplate(item.tid)
        level = t and t.level
      end
      return (level and level > 0) and tostring(level) or ""
    end },
  }, function(item)
    clearStatus()
    page.tid:SetText(tostring(item.tid))
    page.label:SetText(item.favorite or item.name or ACA:ItemName(item.tid) or "")
  end)
  list:SetPoint("TOPLEFT", page, "TOPLEFT", 0, -74)
  local head = W.Label(page, L["ITEM"], "GameFontDisableSmall")
  head:SetPoint("BOTTOMLEFT", list, "TOPLEFT", 34, 2)
  local headTid = W.Label(page, "TID", "GameFontDisableSmall")
  headTid:SetPoint("BOTTOMRIGHT", list, "TOPRIGHT", -44, 2)
  headTid:SetJustifyH("RIGHT")
  local headLevel = W.Label(page, L["LEVEL_SHORT"], "GameFontDisableSmall")
  headLevel:SetPoint("BOTTOMRIGHT", list, "TOPRIGHT", -8, 2)
  headLevel:SetJustifyH("RIGHT")

  -- Catégories (onglets du catalogue) et recherche par nom ou TID.
  local tabs = {}
  local search = W.Edit(page, 100)
  local count = W.Label(page, "", "GameFontDisableSmall")
  local classButton
  local function refresh()
    for c, b in pairs(tabs) do
      if c == category then b:Disable() else b:Enable() end
    end
    if catalog then
      -- Index du catalogue : dit aussi si ce client connaît les classes et les tables du serveur.
      ACA:ItemIndex()
      classButton:SetShown(ACA.itemDetails)
      if ACA.itemServerCount then
        note:SetText(format(L["ITEMS_NOTE_SERVER"], ACA.itemServerCount))
      else
        note:SetText(format(L["ITEMS_NOTE_CATALOG"], ArchRust.GetNumItemTemplates()))
      end
    end
    if category == "favorites" then
      table.sort(favorites, function(a, b) return a.tid < b.tid end)
      local items = {}
      for _, f in ipairs(favorites) do
        local t = ACA:ItemTemplate(f.tid)
        items[#items + 1] = { tid = f.tid, name = f.name or (t and t.name), favorite = f.name, icon = t and t.icon, level = t and t.level or 0 }
      end
      list:SetItems(items)
      count:SetText(format(L["ITEMS_COUNT"], #items))
      return
    end
    local found = ACA:SearchItems(search:GetText(), category ~= "all" and category or nil, ns.CLASSES[classIndex])
    list:SetItems(found)
    count:SetText(format(L["ITEMS_COUNT"], #found))
  end
  page.refresh = refresh
  local step = math.floor((PAGE_W + 6) / #CATEGORIES)
  for i, c in ipairs(CATEGORIES) do
    local b = W.Button(page, L["CAT_" .. c], step - 6, function()
      category = c
      list:Reset({})
      refresh()
    end)
    b:SetPoint("TOPLEFT", page, "TOPLEFT", (i - 1) * step, 0)
    tabs[c] = b
    if not catalog and c ~= "favorites" then b:Hide() end
  end
  local searchLabel = W.Label(page, L["SEARCH"], "GameFontHighlight")
  searchLabel:SetPoint("TOPLEFT", page, "TOPLEFT", 0, -34)
  search:SetPoint("TOPLEFT", page, "TOPLEFT", 74, -30)
  search:SetScript("OnTextChanged", function()
    if category == "favorites" then category = "all" end
    list:Reset({})
    refresh()
  end)
  W.Tooltip(search, L["SEARCH"], L["TIP_SEARCH"])
  -- Filtre de classe : clic pour la suivante, molette dans les deux sens. Affiché seulement si le
  -- client donne les classes des objets (voir refresh).
  local function stepClass(delta)
    classIndex = (classIndex + delta) % (#ns.CLASSES + 1)
    local c = ns.CLASSES[classIndex]
    classButton:SetText(format(L["CLASS_FILTER"], c and c.name or L["CLASS_ALL"]))
    if category == "favorites" then category = "all" end
    list:Reset({})
    refresh()
  end
  classButton = W.Button(page, format(L["CLASS_FILTER"], L["CLASS_ALL"]), 150, function() stepClass(1) end, L["TIP_CLASS_FILTER"])
  classButton:SetPoint("TOPLEFT", page, "TOPLEFT", 180, -30)
  classButton:EnableMouseWheel(true)
  classButton:SetScript("OnMouseWheel", function(_, delta) stepClass(delta < 0 and 1 or -1) end)
  classButton:Hide()
  count:SetPoint("BOTTOMLEFT", list, "TOPLEFT", 90, 2)
  count:SetWidth(170)
  count:SetWordWrap(false)
  if not catalog then
    -- Sans catalogue : favoris seulement, et un titre à la place de la recherche.
    searchLabel:SetText(L["FAVORITES"])
    search:Hide()
    count:Hide()
    tabs.favorites:Hide()
  end

  local function row(y, text)
    local l = W.Label(page, text, "GameFontHighlight")
    l:SetPoint("TOPLEFT", page, "TOPLEFT", X, y - 4)
  end

  -- Objet choisi : icône, nom, TID, niveau requis et catégorie.
  local preview = W.ItemIcon(page, 44)
  preview:SetPoint("TOPLEFT", page, "TOPLEFT", X, -30)
  local previewName = W.Label(page, "", "GameFontNormal")
  previewName:SetPoint("TOPLEFT", page, "TOPLEFT", X + 52, -32)
  previewName:SetWidth(PAGE_W - X - 52)
  previewName:SetWordWrap(false)
  local previewInfo = W.Label(page, "", "GameFontHighlightSmall")
  previewInfo:SetPoint("TOPLEFT", page, "TOPLEFT", X + 52, -52)
  previewInfo:SetWidth(PAGE_W - X - 52)
  previewInfo:SetWordWrap(false)
  page.preview, page.previewName, page.previewInfo = preview, previewName, previewInfo

  row(-84, L["RECIPIENT"])
  local recipient = W.Edit(page, 100)
  recipient:SetPoint("TOPLEFT", page, "TOPLEFT", X + LABEL, -84)
  local fromTarget = W.Button(page, L["TARGET"], 56, function()
    local t = ACA:TargetPlayerName()
    if t then recipient:SetText(t) else ACA:Error(L["ERR_NO_PLAYER_TARGET"]) end
  end, L["TIP_TARGET"])
  fromTarget:SetPoint("LEFT", recipient, "RIGHT", 6, 0)
  local me = W.Button(page, L["SELF"], 44, function() recipient:SetText(UnitName("player") or "") end)
  me:SetPoint("LEFT", fromTarget, "RIGHT", 6, 0)

  row(-114, L["TID"])
  page.tid = W.Edit(page, 80)
  page.tid:SetPoint("TOPLEFT", page, "TOPLEFT", X + LABEL, -114)
  page.tid:SetScript("OnTextChanged", function(self, userInput)
    if userInput then clearStatus() end
    local tid = tonumber(self:GetText())
    local t = ACA:ItemTemplate(tid)
    if tid then preview:SetItem(tid, t and t.icon or false) else preview:SetItem(nil, false) end
    previewName:SetText(tid and (ACA:ItemName(tid) or L["UNKNOWN_ITEM"]) or "")
    local info = {}
    if tid then info[1] = format(L["ITEM_TIP_TID"], tid) end
    if t and t.level and t.level > 0 then info[#info + 1] = format(L["ITEM_TIP_LEVEL"], t.level) end
    if t and t.category then info[#info + 1] = L["CAT_" .. t.category] end
    if t and t.server == false then info[#info + 1] = BAD .. L["NOT_ON_SERVER_SHORT"] .. "|r" end
    previewInfo:SetText(table.concat(info, " · "))
  end)

  row(-144, L["QUANTITY"])
  local qty = W.Edit(page, 50)
  qty:SetPoint("TOPLEFT", page, "TOPLEFT", X + LABEL, -144)
  qty:SetText("1")
  local bound = W.Check(page, L["NOT_TRADABLE"], function() end)
  bound:SetPoint("LEFT", qty, "RIGHT", 14, 0)

  -- Ligne d'état : elle prend la place de la note tant qu'il y a quelque chose à dire.
  local function showStatus(color, text)
    status:SetText(color .. text .. "|r")
    status:Show()
    note:Hide()
  end
  function clearStatus()
    status:Hide()
    note:Show()
  end

  -- Envoi de /create ou /additem ; l'issue arrive par ACA.resultHandlers.
  local sentTid
  local function give(command, args)
    local quantity = tonumber(qty:GetText())
    if quantity and (quantity < 1 or quantity > MAX_QUANTITY) then
      ACA:Error(format(L["ERR_QUANTITY"], MAX_QUANTITY))
      return showStatus(BAD, ACA.lastError)
    end
    sentTid = tonumber(page.tid:GetText())
    if ACA:Run(command, args) then
      showStatus(WAITING, L["RESULT_SENT"])
    else
      showStatus(BAD, ACA.lastError)
    end
  end
  local function onResult(kind, text)
    if kind == "ok" then return showStatus(GOOD, text) end
    local message = kind == "timeout" and explainSilence(sentTid) or explainRefusal(text, sentTid)
    ACA:Error(message)
    showStatus(BAD, message)
  end
  ACA.resultHandlers.create, ACA.resultHandlers.additem = onResult, onResult

  local create = W.Button(page, L["CREATE"], 150, function()
    local who = strtrim(recipient:GetText() or "")
    if who == "" then who = UnitName("player") or "" end
    give("create", { who, page.tid:GetText(), qty:GetText(), bound:GetChecked() and 1 or 0 })
  end, L["TIP_CREATE"], "create")
  create:SetPoint("TOPLEFT", page, "TOPLEFT", X, -178)
  -- /additem : raccourci du serveur pour soi-même (objet toujours échangeable).
  local additem = W.Button(page, L["ADDITEM"], 150, function()
    give("additem", { page.tid:GetText(), qty:GetText() })
  end, L["TIP_ADDITEM"], "additem")
  additem:SetPoint("LEFT", create, "RIGHT", 6, 0)

  row(-214, L["FAVORITE_NAME"])
  page.label = W.Edit(page, 160)
  page.label:SetPoint("TOPLEFT", page, "TOPLEFT", X + LABEL, -214)
  local add = W.Button(page, L["ADD_FAVORITE"], 150, function()
    local tid = tonumber(page.tid:GetText())
    if not tid then return ACA:Error(format(L["ERR_INT"], page.tid:GetText() or "")) end
    local label = strtrim(page.label:GetText() or "")
    if label == "" then label = ACA:ItemName(tid) end
    for _, item in ipairs(favorites) do
      if item.tid == tid then
        item.name = label
        return refresh()
      end
    end
    tinsert(favorites, { tid = tid, name = label })
    refresh()
  end)
  add:SetPoint("TOPLEFT", page, "TOPLEFT", X, -246)
  -- Retire le favori de l'objet choisi (champ TID).
  local remove = W.Button(page, L["REMOVE"], 100, function()
    local tid = tonumber(page.tid:GetText())
    for i, item in ipairs(favorites) do
      if item.tid == tid then
        tremove(favorites, i)
        list.selected = nil
        return refresh()
      end
    end
  end, L["TIP_REMOVE_FAVORITE"])
  remove:SetPoint("LEFT", add, "RIGHT", 6, 0)

  note = W.Label(page, catalog and "" or L["ITEMS_NOTE"], "GameFontDisableSmall")
  note:SetPoint("TOPLEFT", page, "TOPLEFT", X, -282)
  note:SetWidth(PAGE_W - X)
  note:SetWordWrap(true)
  status = W.Label(page, "", "GameFontHighlightSmall")
  status:SetPoint("TOPLEFT", page, "TOPLEFT", X, -282)
  status:SetWidth(PAGE_W - X)
  status:SetWordWrap(true)
  status:Hide()

  ACA:RegisterMessage("ARCHCOREADMIN_ITEMS", function()
    if category == "favorites" then refresh() else list:Refresh() end
    page.tid:GetScript("OnTextChanged")(page.tid)
  end)
  function page:OnShow()
    if strtrim(recipient:GetText() or "") == "" then recipient:SetText(UnitName("player") or "") end
    refresh()
  end
  page.list, page.search, page.categories, page.addFavorite = list, search, tabs, add
  page.status, page.note, page.classButton, page.qty = status, note, classButton, qty
end)
