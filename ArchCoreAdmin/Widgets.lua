-- Petits constructeurs de frames (le rôle de FrameLib dans AzerothAdmin) : boutons avec
-- info-bulle, champs de saisie, cases à cocher, libellés, et une liste qui défile à la molette.
-- Un bouton lié à une commande du catalogue est grisé quand le niveau MJ ne suffit pas.
local addonName, ns = ...
local ACA = LibStub("AceAddon-3.0"):GetAddon("ArchCoreAdmin")
local L = LibStub("AceLocale-3.0"):GetLocale("ArchCoreAdmin")

local W = {}
ns.W = W

local function showTip(self)
  if not self.tipTitle then return end
  GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
  GameTooltip:SetText(self.tipTitle)
  if self.tipText then GameTooltip:AddLine(self.tipText, 1, 1, 1) end
  local c = self.command and ns.Catalog[self.command]
  if c then
    GameTooltip:AddLine(c.usage, 0.6, 0.8, 1)
    GameTooltip:AddLine(format(L["TIP_LEVEL"], ACA:RequiredLevel(c.name)), 0.7, 0.7, 0.7)
  end
  GameTooltip:Show()
end

local function hideTip() GameTooltip:Hide() end

function W.Tooltip(frame, title, text)
  frame.tipTitle, frame.tipText = title, text
  frame:SetScript("OnEnter", showTip)
  frame:SetScript("OnLeave", hideTip)
end

function W.Label(parent, text, font)
  local fs = parent:CreateFontString(nil, "OVERLAY", font or "GameFontNormal")
  fs:SetJustifyH("LEFT")
  fs:SetText(text or "")
  return fs
end

-- `command` : nom du catalogue, pour griser le bouton et compléter l'info-bulle.
function W.Button(parent, text, width, onClick, tip, command)
  local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
  b:SetSize(width or 96, 22)
  b:SetText(text)
  b:SetScript("OnClick", function(self, button) onClick(self, button) end)
  b.command = command
  W.Tooltip(b, text, tip)
  if command then tinsert(ACA.widgets, b) end
  return b
end

function W.Edit(parent, width, onEnter)
  local e = CreateFrame("EditBox", nil, parent, "InputBoxTemplate")
  e:SetSize(width or 80, 22)
  e:SetAutoFocus(false)
  e:SetScript("OnEnterPressed", function(self)
    self:ClearFocus()
    if onEnter then onEnter(self) end
  end)
  return e
end

function W.Check(parent, text, onClick)
  local cb = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
  cb.Text:SetText(text)
  cb:SetScript("OnClick", function(self) onClick(self:GetChecked()) end)
  return cb
end

-- Cadre sombre bordé d'or, comme les fenêtres du client.
function W.Panel(parent)
  local f = CreateFrame("Frame", nil, parent, "BackdropTemplate")
  f:SetBackdrop(ArchRust.DefaultBackdrop)
  f:SetBackdropColor(0, 0, 0, 0.45)
  f:SetBackdropBorderColor(0.45, 0.36, 0.2, 1)
  return f
end

-- Liste de `rows` lignes : `list:SetItems(t, format)` où `format(item)` rend le texte de la
-- ligne ; molette pour défiler ; `onSelect(item, index)` au clic. Les ScrollFrame d'ArchRust ne
-- découpent pas leur contenu : on décale les données plutôt que les lignes (FauxScrollFrame).
function W.List(parent, width, rows, onSelect)
  local ROW = 16
  local list = W.Panel(parent)
  list:SetSize(width, rows * ROW + 8)
  list.items, list.offset, list.rows = {}, 0, {}
  for i = 1, rows do
    local r = CreateFrame("Button", nil, list, "BackdropTemplate")
    r:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8" })
    r:SetBackdropColor(0, 0, 0, 0)
    r:SetPoint("TOPLEFT", list, "TOPLEFT", 4, -4 - (i - 1) * ROW)
    r:SetSize(width - 8, ROW)
    r.text = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    r.text:SetPoint("LEFT", r, "LEFT", 4, 0)
    r.text:SetWidth(width - 16)
    r.text:SetJustifyH("LEFT")
    r.text:SetWordWrap(false)
    r:SetScript("OnClick", function(self)
      local index = list.offset + i
      local item = list.items[index]
      if not item then return end
      list.selected = index
      list:Refresh()
      if onSelect then onSelect(item, index) end
    end)
    list.rows[i] = r
  end
  list:EnableMouseWheel(true)
  list:SetScript("OnMouseWheel", function(self, delta)
    local max = math.max(0, #self.items - rows)
    self.offset = Clamp(self.offset - delta * 3, 0, max)
    self:Refresh()
  end)
  function list:SetItems(items, fmt)
    self.items, self.fmt = items or {}, fmt or tostring
    if self.selected and self.selected > #self.items then self.selected = nil end
    self.offset = Clamp(self.offset, 0, math.max(0, #self.items - rows))
    self:Refresh()
  end
  function list:ScrollToEnd()
    self.offset = math.max(0, #self.items - rows)
    self:Refresh()
  end
  function list:Refresh()
    for i, r in ipairs(self.rows) do
      local index = self.offset + i
      local item = self.items[index]
      r.text:SetText(item and self.fmt(item) or "")
      r:SetBackdropColor(0.85, 0.62, 0.25, index == self.selected and item and 0.35 or 0)
    end
  end
  return list
end

-- Icône d'objet du jeu (texture du client donnée par le catalogue d'ArchRust) dans une case bordée
-- d'or, comme les cases de l'inventaire. `icon:SetItem(tid)` ; sans icône connue : « ? ».
function W.ItemIcon(parent, size)
  local f = W.Panel(parent)
  f:SetSize(size, size)
  f:SetBackdropColor(0, 0, 0, 0.6)
  f.tex = f:CreateTexture(nil, "ARTWORK")
  f.tex:SetPoint("TOPLEFT", f, "TOPLEFT", 2, -2)
  f.tex:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -2, 2)
  f.tex:Hide()
  f.none = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  f.none:SetPoint("CENTER", f, "CENTER", 0, 0)
  f.none:SetText("?")
  f.none:Hide()
  function f:SetItem(tid, icon)
    if icon == nil and tid then
      local t = ACA:ItemTemplate(tid)
      icon = t and t.icon
    end
    self.icon = icon
    if icon and icon ~= "" then
      self.tex:SetTexture(icon)
      self.tex:Show()
      self.none:Hide()
    else
      self.tex:Hide()
      self.none:SetShown(tid ~= nil)
    end
  end
  return f
end

-- Caractéristiques des modèles (`stats`) : colonnes des tables du serveur → libellés de Locales.lua.
-- « Linghtning » : orthographe de la colonne. Les valeurs nulles ou absentes ne s'affichent pas.
local ELEMENTS = { "Magic", "Water", "Fire", "Earth", "Air", "Poison", "Ice", "Linghtning" }
local ATTACK_STATS = {
  { "ATK Speed", "STAT_ATK_SPEED" }, { "ATK Range", "STAT_ATK_RANGE" }, { "Physical_ATKRate", "STAT_PHYS_RATE" },
  { "Magic_ATKRate", "STAT_MAGIC_RATE" },
}
local DEFENSE_STATS = {
  { "Physical_Defense_Point", "STAT_PHYS_DEF" }, { "PDR", "STAT_PDR" }, { "BlockRate", "STAT_BLOCK" },
}
local BONUS_STATS = {
  { "CON_Bonus_Point", "STAT_CON" }, { "STR_Bonus_Point", "STAT_STR" }, { "DEX_Bonus_Point", "STAT_DEX" },
  { "INT_Bonus_Point", "STAT_INT" }, { "Wis_Bonus_Point", "STAT_WIS" }, { "HP", "STAT_HP" }, { "SP", "STAT_SP" },
  { "MP", "STAT_MP" }, { "Hp_Buff", "STAT_HP_BUFF" }, { "Mp_Buff", "STAT_MP_BUFF" }, { "Attack_Buff", "STAT_ATK_BUFF" },
  { "Defense_Buff", "STAT_DEF_BUFF" }, { "Run_Buff", "STAT_RUN_BUFF" }, { "Rank", "STAT_RANK" }, { "DUR", "STAT_DUR" },
}

local function statLines(s)
  local lines = {}
  local function add(label, value) lines[#lines + 1] = format(L["STAT_LINE"], label, value) end
  local function range(minKey, maxKey, label)
    local lo, hi = s[minKey] or 0, s[maxKey] or 0
    if lo ~= 0 or hi ~= 0 then add(label, format("%g - %g", lo, hi)) end
  end
  local function singles(list)
    for _, e in ipairs(list) do
      local v = s[e[1]]
      if v and v ~= 0 then add(L[e[2]], format("%g", v)) end
    end
  end
  range("Physical_Min_Damage", "Physical_Max_Damage", L["STAT_PHYS_DMG"])
  for _, e in ipairs(ELEMENTS) do range(e .. "_Min_Damage", e .. "_Max_Damage", format(L["STAT_DMG_OF"], L["ELEM_" .. e])) end
  singles(ATTACK_STATS)
  singles(DEFENSE_STATS)
  for _, e in ipairs(ELEMENTS) do
    local point, rate = s[e .. "_Defense_Point"], s[e .. "_Defense_Rate"]
    if point and point ~= 0 then add(format(L["STAT_DEF_OF"], L["ELEM_" .. e]), format("%g", point)) end
    if rate and rate ~= 0 then add(format(L["STAT_RES_OF"], L["ELEM_" .. e]), format("%g", rate)) end
  end
  singles(BONUS_STATS)
  return lines
end

-- Info-bulle d'un objet : nom, TID, niveau requis, catégorie, partie du corps, pile, puis, si le client
-- les donne, classes, emplacements et caractéristiques ; `extra` : lignes en plus.
function W.ItemTooltip(owner, item, extra)
  if not item then return end
  local t = ACA:ItemTemplate(item.tid) or item
  GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
  GameTooltip:SetText(t.name or item.name or ACA:ItemName(item.tid) or ("TID " .. item.tid))
  GameTooltip:AddLine(format(L["ITEM_TIP_TID"], item.tid), 0.7, 0.7, 0.7)
  if t.server == false then GameTooltip:AddLine(L["ITEM_TIP_NOT_ON_SERVER"], 1, 0.35, 0.35) end
  if t.level and t.level > 0 then GameTooltip:AddLine(format(L["ITEM_TIP_LEVEL"], t.level), 1, 1, 1) end
  if t.category then GameTooltip:AddLine(L["CAT_" .. t.category], 0.85, 0.7, 0.4) end
  local part = ns.ITEM_PARTS[t.part]
  if part then GameTooltip:AddLine(format(L["ITEM_TIP_PART"], L[part]), 0.85, 0.7, 0.4) end
  local classes = ACA:ItemClassNames(t)
  if classes then GameTooltip:AddLine(format(L["ITEM_TIP_CLASSES"], table.concat(classes, ", ")), 0.85, 0.7, 0.4) end
  local lo, hi = t.minSocket or 0, t.maxSocket or 0
  if hi > lo then
    GameTooltip:AddLine(format(L["ITEM_TIP_SOCKETS_RANGE"], lo, hi), 0.6, 0.8, 1)
  elseif hi > 0 then
    GameTooltip:AddLine(format(L["ITEM_TIP_SOCKETS"], hi), 0.6, 0.8, 1)
  end
  for _, line in ipairs(t.stats and statLines(t.stats) or {}) do GameTooltip:AddLine(line, 1, 1, 1) end
  if t.stack and t.stack > 1 then GameTooltip:AddLine(format(L["ITEM_TIP_STACK"], t.stack), 0.7, 0.7, 0.7) end
  for _, line in ipairs(extra or {}) do GameTooltip:AddLine(line, 0.6, 0.8, 1) end
  GameTooltip:Show()
end

-- Liste d'objets avec leur icône : `rows` lignes de 26 px ; `columns` : colonnes à droite du nom,
-- `{ { width = 44, text = function(item) … end }, … }` (de gauche à droite) ; `onSelect(item, index)`
-- au clic ; molette pour défiler (décalage des données, comme W.List). Les éléments sont des tables
-- `{ tid, name?, icon? … }` : nom et icône manquants sont cherchés dans le catalogue.
-- `tipExtra(item)` : lignes ajoutées à l'info-bulle.
-- `opts.noIcon` : liste d'autre chose que des objets (monstres), sans icône ; `opts.tooltip(owner, item)`
-- remplace alors l'info-bulle d'objet.
function W.ItemList(parent, width, rows, columns, onSelect, tipExtra, opts)
  local ROW = 26
  opts = opts or {}
  local list = W.Panel(parent)
  list:SetSize(width, rows * ROW + 8)
  list.items, list.offset, list.rows = {}, 0, {}
  columns = columns or {}
  local right = 4
  for _, c in ipairs(columns) do right = right + c.width + 6 end
  for i = 1, rows do
    local r = CreateFrame("Button", nil, list, "BackdropTemplate")
    r:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8" })
    r:SetBackdropColor(0, 0, 0, 0)
    r:SetPoint("TOPLEFT", list, "TOPLEFT", 4, -4 - (i - 1) * ROW)
    r:SetSize(width - 8, ROW)
    r.text = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    if opts.noIcon then
      r.text:SetPoint("LEFT", r, "LEFT", 4, 0)
      r.text:SetWidth(width - 8 - 4 - right)
    else
      r.icon = W.ItemIcon(r, ROW - 4)
      r.icon:SetPoint("LEFT", r, "LEFT", 2, 0)
      r.text:SetPoint("LEFT", r.icon, "RIGHT", 6, 0)
      r.text:SetWidth(width - 8 - (ROW - 4) - 8 - right)
    end
    r.text:SetJustifyH("LEFT")
    r.text:SetWordWrap(false)
    r.cols = {}
    local x = -4
    for c = #columns, 1, -1 do
      local fs = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
      fs:SetPoint("RIGHT", r, "RIGHT", x, 0)
      fs:SetWidth(columns[c].width)
      fs:SetJustifyH("RIGHT")
      fs:SetWordWrap(false)
      r.cols[c] = fs
      x = x - columns[c].width - 6
    end
    r:SetScript("OnClick", function()
      local index = list.offset + i
      local item = list.items[index]
      if not item then return end
      list.selected = index
      list:Refresh()
      if onSelect then onSelect(item, index) end
    end)
    r:SetScript("OnEnter", function(self)
      local item = list.items[list.offset + i]
      if not item then return end
      if opts.tooltip then
        opts.tooltip(self, item)
      else
        W.ItemTooltip(self, item, tipExtra and tipExtra(item))
      end
    end)
    r:SetScript("OnLeave", hideTip)
    list.rows[i] = r
  end
  list:EnableMouseWheel(true)
  list:SetScript("OnMouseWheel", function(self, delta)
    local max = math.max(0, #self.items - rows)
    self.offset = Clamp(self.offset - delta * 3, 0, max)
    self:Refresh()
  end)
  function list:SetItems(items)
    self.items = items or {}
    if self.selected and self.selected > #self.items then self.selected = nil end
    self.offset = Clamp(self.offset, 0, math.max(0, #self.items - rows))
    self:Refresh()
  end
  function list:Reset(items)
    self.selected, self.offset = nil, 0
    self:SetItems(items)
  end
  function list:Refresh()
    for i, r in ipairs(self.rows) do
      local index = self.offset + i
      local item = self.items[index]
      r:SetShown(item ~= nil)
      if item then
        if r.icon then r.icon:SetItem(item.tid, item.icon) end
        r.text:SetText(item.name or ACA:ItemName(item.tid) or "?")
        for c, fs in ipairs(r.cols) do fs:SetText(columns[c].text(item) or "") end
        r:SetBackdropColor(0.85, 0.62, 0.25, index == self.selected and 0.35 or 0)
      end
    end
  end
  return list
end

-- Grise les boutons des commandes que le niveau MJ connu ne permet pas.
function ACA:UpdateWidgets()
  for _, b in ipairs(self.widgets) do
    if self:CanUse(b.command) then b:Enable() else b:Disable() end
  end
  if self.levelText then self.levelText:SetText(self:LevelText()) end
  self:SendMessage("ARCHCOREADMIN_REFRESH")
end
