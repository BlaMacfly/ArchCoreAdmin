-- Onglet Objets (la recherche d'objets d'AzerothAdmin) : /create "nom" <TID> <quantité> <0|1>,
-- et /additem <TID> [quantité] pour soi.
-- ArchCore n'a pas de commande de recherche : les objets se choisissent dans le catalogue du client
-- (ArchRust.SearchItems : nom, icône, niveau requis, catégorie), par catégorie et par nom, ou se
-- désignent par leur TID. Sans ce catalogue (client plus ancien), seuls la saisie du TID et les
-- favoris restent ; le nom de l'objet est alors appris dans la réponse du serveur (« 5 × Potion de
-- vie (TID 190) donné(s) »).
local addonName, ns = ...
local ACA = LibStub("AceAddon-3.0"):GetAddon("ArchCoreAdmin")
local L = LibStub("AceLocale-3.0"):GetLocale("ArchCoreAdmin")
local W = ns.W

-- Catégories d'ArchRust.SearchItems (« all » : toutes), puis les favoris.
local CATEGORIES = { "all", "weapon", "armor", "jewel", "mount", "usable", "other", "favorites" }
-- Objets listés au plus pour une recherche (le total trouvé est affiché à côté).
local MAX_RESULTS = 1000
-- Largeur de la page (fenêtre moins les marges), de la liste ; lignes de la liste.
local PAGE_W, LIST_W, ROWS = 656, 330, 10

ns.RegisterSection("items", "TAB_ITEMS", function(page)
  local favorites = ACA.db.global.items
  local catalog = ACA:HasItemCatalog()
  local X, LABEL = LIST_W + 14, 100
  local category = catalog and "all" or "favorites"

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
  local search = W.Edit(page, 150)
  local count = W.Label(page, "", "GameFontDisableSmall")
  local function refresh()
    for c, b in pairs(tabs) do
      if c == category then b:Disable() else b:Enable() end
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
    local found, total = ACA:SearchItems(strtrim(search:GetText() or ""), category ~= "all" and category or nil, MAX_RESULTS)
    list:SetItems(found)
    count:SetText(total > #found and format(L["ITEMS_COUNT_OF"], #found, total) or format(L["ITEMS_COUNT"], total))
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
  count:SetPoint("TOPLEFT", page, "TOPLEFT", 232, -34)
  count:SetWidth(LIST_W - 232)
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
  page.tid:SetScript("OnTextChanged", function(self)
    local tid = tonumber(self:GetText())
    local t = ACA:ItemTemplate(tid)
    if tid then preview:SetItem(tid, t and t.icon or false) else preview:SetItem(nil, false) end
    previewName:SetText(tid and (ACA:ItemName(tid) or L["UNKNOWN_ITEM"]) or "")
    local info = {}
    if tid then info[1] = format(L["ITEM_TIP_TID"], tid) end
    if t and t.level and t.level > 0 then info[#info + 1] = format(L["ITEM_TIP_LEVEL"], t.level) end
    if t and t.category then info[#info + 1] = L["CAT_" .. t.category] end
    previewInfo:SetText(table.concat(info, " · "))
  end)

  row(-144, L["QUANTITY"])
  local qty = W.Edit(page, 50)
  qty:SetPoint("TOPLEFT", page, "TOPLEFT", X + LABEL, -144)
  qty:SetText("1")
  local bound = W.Check(page, L["NOT_TRADABLE"], function() end)
  bound:SetPoint("LEFT", qty, "RIGHT", 14, 0)

  local create = W.Button(page, L["CREATE"], 150, function()
    local who = strtrim(recipient:GetText() or "")
    if who == "" then who = UnitName("player") or "" end
    ACA:Run("create", { who, page.tid:GetText(), qty:GetText(), bound:GetChecked() and 1 or 0 })
  end, L["TIP_CREATE"], "create")
  create:SetPoint("TOPLEFT", page, "TOPLEFT", X, -178)
  -- /additem : raccourci du serveur pour soi-même (objet toujours échangeable).
  local additem = W.Button(page, L["ADDITEM"], 150, function()
    ACA:Run("additem", { page.tid:GetText(), qty:GetText() })
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

  local note = W.Label(page, catalog and format(L["ITEMS_NOTE_CATALOG"], ArchRust.GetNumItemTemplates()) or L["ITEMS_NOTE"], "GameFontDisableSmall")
  note:SetPoint("TOPLEFT", page, "TOPLEFT", X, -282)
  note:SetWidth(PAGE_W - X)
  note:SetWordWrap(true)

  ACA:RegisterMessage("ARCHCOREADMIN_ITEMS", function()
    if category == "favorites" then refresh() else list:Refresh() end
    page.tid:GetScript("OnTextChanged")(page.tid)
  end)
  function page:OnShow()
    if strtrim(recipient:GetText() or "") == "" then recipient:SetText(UnitName("player") or "") end
    refresh()
  end
  page.list, page.search, page.categories, page.addFavorite = list, search, tabs, add
end)
