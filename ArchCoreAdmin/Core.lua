-- ArchCore Admin : panneau MJ pour ArchRust, sur le principe d'AzerothAdmin (WoW 3.3.5 /
-- AzerothCore). Chaque bouton tape une commande MJ d'ArchCore (« /kill "Nom" », « /move x,z »…) ;
-- le client l'envoie au serveur dans la discussion, comme le panneau « Admin Commands »
-- d'Archonia ; les réponses du serveur (messages système) sont lues pour remplir le panneau
-- et le journal (voir Replies.lua).
--   * AceAddon/AceDB : objet AddOn, réglages, points de téléportation, objets favoris, journal ;
--   * AceConsole : /aca ; AceEvent : entrée en jeu, cible ; AceTimer : délais des réponses.
local addonName, ns = ...

local ACA = LibStub("AceAddon-3.0"):NewAddon(ns, "ArchCoreAdmin", "AceConsole-3.0", "AceEvent-3.0", "AceTimer-3.0")
local L = LibStub("AceLocale-3.0"):GetLocale("ArchCoreAdmin")
_G.ArchCoreAdmin = ACA

local MAX_LOG = 300
local MAX_HISTORY = 30
-- Une réponse du serveur arrivée plus tard n'est plus rattachée à la commande envoyée.
local REPLY_TIMEOUT = 5

local defaults = {
  profile = {
    confirm = true,        -- confirmation des commandes marquées `confirm` dans le catalogue
    showReplies = true,    -- laisser les réponses du serveur dans la discussion
    probe = true,          -- détecter le niveau MJ à l'entrée en jeu
    launcher = true,
    launcherPos = { x = 8, y = -200 },
    framePos = { x = 180, y = -90 },
    binding = "CTRL-SHIFT-A",
    tab = "gm",
    showUnsupported = false,
  },
  global = { teleports = {}, items = {}, itemNames = {}, levels = {}, monsters = {} },
  char = { log = {}, history = {} },
}

-- Villages de départ d'ArchCore (StartPosition.<race> de world.conf), ajoutés au premier lancement.
local SEED_TELEPORTS = {
  { name = "Anchorville", x = -475955, z = -66219 },
  { name = "Golundo", x = 136249, z = 512721 },
  { name = "Norine", x = 517472, z = 38020 },
  { name = "Cien", x = -591942, z = 335917 },
}

function ACA:OnInitialize()
  self.db = LibStub("AceDB-3.0"):New("ArchCoreAdminDB", defaults, true)
  local g = self.db.global
  if not g.seeded then
    for _, t in ipairs(SEED_TELEPORTS) do tinsert(g.teleports, CopyTable(t)) end
    g.seeded = true
  end
  self.pending = {}
  self.rates = {}
  self.widgets = {}
  -- Issue d'une commande pour l'onglet qui l'a envoyée : `resultHandlers[nom](kind, text)`.
  self.resultHandlers = {}
  self:RegisterChatCommand("aca", "SlashCommand")
  self:RegisterChatCommand("archcoreadmin", "SlashCommand")
end

function ACA:OnEnable()
  self:RegisterEvent("PLAYER_ENTERING_WORLD")
  self:RegisterEvent("PLAYER_TARGET_CHANGED", "UpdateWidgets")
  self:RegisterEvent("NAME_PLATE_UNIT_ADDED")
  -- ArchCore répond par un message de discussion de type « système » (AGPMCHATTING), qu'ArchRust
  -- remet en CHAT_MSG_SAY sans auteur ; CHAT_MSG_SYSTEM est écouté aussi au cas où le client les
  -- distinguerait un jour. Le filtre peut masquer la réponse.
  ChatFrame_AddMessageEventFilter("CHAT_MSG_SYSTEM", function(_, _, msg)
    return ACA:OnSystemMessage(msg)
  end)
  ChatFrame_AddMessageEventFilter("CHAT_MSG_SAY", function(_, _, msg, author)
    if author == nil or author == "" then return ACA:OnSystemMessage(msg) end
  end)
  self:CreateFrames()
  self:ApplyBinding()
  local key = self.db.profile.binding
  self:Print(format(L["LOADED"], key ~= "" and key or "MJ"))
end

function ACA:PLAYER_ENTERING_WORLD(_, isLogin, isReload)
  if self.db.profile.probe and (isLogin or isReload or self.gmLevel == nil) then
    self:ProbeLevel()
  end
end

---------------------------------------------------------------------------------------------------
-- Niveau MJ
---------------------------------------------------------------------------------------------------

-- Le client ne transmet pas le niveau MJ aux AddOns : on envoie « /SetExp » sans argument.
-- ArchCore vérifie le niveau avant les arguments, donc la commande n'a aucun effet et répond :
--   « Commande inconnue : /SetExp »                    → compte sans droits (niveau 0) ;
--   « Niveau MJ 3 requis pour /SetExp (le vôtre : N) » → niveau N exact ;
--   « /SetExp : argument manquant. Syntaxe : … »        → niveau 3 ou plus.
-- La demande figure dans le journal MJ du serveur, comme toute commande.
-- ArchRust ne remet pas aux AddOns les messages qui commencent par « / » : la troisième réponse se
-- perd, et un compte sans droits n'en reçoit aucune. Le silence est donc levé par « /GetExp » (niveau
-- 1, réponse « Taux d'expérience : … ») : une réponse veut dire que le niveau suffisait pour /SetExp.
function ACA:ProbeLevel()
  self.probing = true
  self:SetGMLevel(nil, nil)
  self:SendLine("/SetExp", "SetExp", { probe = "set" })
end

function ACA:OnProbeSilence(entry)
  if not self.probing then return end
  if entry.probe == "set" then
    self:SendLine("/GetExp", "GetExp", { probe = "get" })
  else
    self.probing = nil
    self:Print(L["PROBE_NO_REPLY"])
    self:UpdateWidgets()
  end
end

function ACA:SetGMLevel(level, exact)
  if self.gmLevel == level and self.gmLevelExact == exact then return end
  self.gmLevel, self.gmLevelExact = level, exact
  self:UpdateWidgets()
  self:SendMessage("ARCHCOREADMIN_LEVEL", level, exact)
end

-- Niveau requis : celui appris du serveur, sinon celui du catalogue.
function ACA:RequiredLevel(name)
  local c = ns.Catalog[name]
  return self.db.global.levels[name] or (c and c.level) or 1
end

-- Faux seulement si l'on sait que le compte n'a pas le niveau demandé.
function ACA:CanUse(name)
  local c = ns.Catalog[name]
  if c and not c.archcore then return false end
  if self.gmLevel == nil then return true end
  if self.gmLevelExact then return self.gmLevel >= self:RequiredLevel(name) end
  -- Niveau minimal seulement (« 3 ou plus ») : rien n'est grisé, sauf pour un compte à 0.
  return self.gmLevel > 0
end

---------------------------------------------------------------------------------------------------
-- Construction et envoi des commandes
---------------------------------------------------------------------------------------------------

local function trim(s) return s and strtrim(tostring(s)) or "" end

-- Nom de personnage entre guillemets : ArchCore n'accepte ni guillemet ni saut de ligne dedans.
function ACA:Quote(name)
  name = trim(name)
  if name == "" then return nil, L["ERR_NAME_EMPTY"] end
  if name:find('["\r\n]') then return nil, format(L["ERR_NAME_CHARS"], name) end
  return '"' .. name .. '"'
end

local function formatFloat(v)
  local s = format("%.4f", v):gsub("0+$", ""):gsub("%.$", ".0")
  return s
end

local converters = {
  int = function(v)
    local n = tonumber(trim(v))
    if not n or n ~= math.floor(n) then return nil, format(L["ERR_INT"], trim(v)) end
    return format("%d", n)
  end,
  float = function(v)
    local n = tonumber((trim(v):gsub(",", ".")))
    if not n then return nil, format(L["ERR_NUMBER"], trim(v)) end
    return formatFloat(n)
  end,
  name = function(v) return ACA:Quote(v) end,
  coords = function(v)
    local x, z = tonumber(v and v[1]), tonumber(v and v[2])
    if not x or not z then return nil, L["ERR_COORDS"] end
    return format("%.0f,%.0f", x, z)
  end,
}

local function isEmpty(v) return v == nil or (type(v) == "string" and trim(v) == "") end

-- Ligne « /commande arguments » d'après le catalogue ; `nil, erreur` si un argument est invalide.
function ACA:Build(name, args)
  local c = ns.Catalog[name]
  if not c then return nil, format(L["ERR_UNKNOWN_CMD"], name) end
  local parts, stopped = { "/" .. c.name }, false
  for i, spec in ipairs(c.args) do
    local v = args[i]
    if isEmpty(v) then
      if not spec.opt then return nil, format(L["ERR_MISSING"], c.usage) end
      stopped = true
    else
      -- Arguments positionnels : un facultatif absent ne peut pas être suivi d'un autre.
      if stopped then return nil, format(L["ERR_MISSING"], c.usage) end
      local s, err = converters[spec[1]](v)
      if not s then return nil, err end
      parts[#parts + 1] = s
    end
  end
  return table.concat(parts, " ")
end

-- Envoie une commande du catalogue : `ACA:Run("level", { 50, "Testeur" })`.
-- `confirmText` : phrase de confirmation (sinon la ligne elle-même).
function ACA:Run(name, args, confirmText)
  local line, err = self:Build(name, args or {})
  if not line then
    self:Error(err)
    return false
  end
  if not self:CanUse(name) then
    self:Error(format(L["ERR_LEVEL"], name, self:RequiredLevel(name), self.gmLevel or 0))
    return false
  end
  local c = ns.Catalog[name]
  if c.confirm and self.db.profile.confirm then
    self:Confirm(confirmText or line, function() self:SendLine(line, name) end)
  else
    self:SendLine(line, name)
  end
  return true
end

-- Commande libre (onglet MJ) : envoyée telle quelle, une seule ligne.
function ACA:RunFree(text)
  text = trim(text):gsub("[\r\n]+", " ")
  if text == "" then return end
  if text:sub(1, 1) ~= "/" then text = "/" .. text end
  local h = self.db.char.history
  tDeleteItem(h, text)
  tinsert(h, 1, text)
  while #h > MAX_HISTORY do tremove(h) end
  self:SendLine(text, text:match("^/(%S+)"))
end

-- Le client envoie au serveur toute commande « / » qu'il ne connaît pas (comme Archonia) ;
-- RunMacroText passe par ce chemin, sans écho « [Nom] /commande » dans la discussion.
function ACA:SendLine(line, name, opts)
  line = line:gsub("[\r\n]+", " ")
  opts = opts or {}
  local entry = { name = name, line = line, time = GetTime(), probe = opts.probe }
  tinsert(self.pending, entry)
  self:ScheduleTimer("OnReplyTimeout", REPLY_TIMEOUT, entry)
  if not opts.probe then self:AddLog(">", line, name) end
  RunMacroText(line)
  self:SendMessage("ARCHCOREADMIN_SENT", name, line)
end

-- Toujours en attente au bout du délai : pas de réponse, et rien n'en dit la raison (voir
-- OnSystemMessage et docs/BESOINS-CLIENT-SERVEUR.md : les refus du serveur n'arrivent pas aux AddOns).
function ACA:OnReplyTimeout(entry)
  if not tIndexOf(self.pending, entry) then return end
  tDeleteItem(self.pending, entry)
  if entry.probe then return self:OnProbeSilence(entry) end
  self:AddLog("!", format(L["NO_REPLY"], entry.line), entry.name)
  self:CommandResult(entry.name, "timeout", entry.line)
end

-- Issue d'une commande : kind = "ok", "refused" (text : raison donnée par le serveur) ou "timeout".
function ACA:CommandResult(name, kind, text)
  local handler = self.resultHandlers[name]
  if handler then handler(kind, text) end
end

---------------------------------------------------------------------------------------------------
-- Journal, messages, confirmation
---------------------------------------------------------------------------------------------------

-- kind : ">" commande envoyée, "<" réponse du serveur, "!" erreur de l'AddOn.
function ACA:AddLog(kind, text, name)
  local log = self.db.char.log
  tinsert(log, { t = time(), k = kind, s = text, c = name })
  while #log > MAX_LOG do tremove(log, 1) end
  self:SendMessage("ARCHCOREADMIN_LOG")
end

function ACA:Error(text)
  self.lastError = text
  self:Print("|cffff5050" .. text .. "|r")
  self:AddLog("!", text)
end

StaticPopupDialogs["ARCHCOREADMIN_CONFIRM"] = {
  text = "%s",
  button1 = YES,
  button2 = NO,
  OnAccept = function(_, data) if data then data() end end,
  -- Position d'origine de la fenêtre partagée StaticPopup1 (interface.lua d'ArchRust).
  OnHide = function(popup)
    popup:ClearAllPoints()
    popup:SetPoint("TOP", UIParent, "TOP", 0, -140)
  end,
  timeout = 0,
  hideOnEscape = true,
}

function ACA:Confirm(text, onAccept)
  local popup = StaticPopup_Show("ARCHCOREADMIN_CONFIRM", format(L["CONFIRM"], text), nil, onAccept)
  -- ArchRust dessine les boutons et champs du panneau par-dessus la fenêtre de confirmation
  -- quand elles se recouvrent : on la pose sous le panneau (remise en place à sa fermeture).
  if popup and self.frame and self.frame:IsShown() then
    popup:ClearAllPoints()
    popup:SetPoint("TOP", self.frame, "BOTTOM", 0, -6)
  end
end

---------------------------------------------------------------------------------------------------
-- Catalogue des objets du client
---------------------------------------------------------------------------------------------------

-- ArchRust donne aux AddOns le catalogue des objets d'ItemTemplateAll.ini (ArchRust.SearchItems,
-- ArchRust.GetItemTemplate, GetItemIcon : nom, icône, niveau requis, catégorie). Un client plus
-- ancien ne l'a pas : l'AddOn revient alors à la saisie du TID et aux noms appris du serveur.
-- Ce fichier est celui du client, ajouts d'Archonia compris : il contient des objets que le serveur
-- ne connaît pas. Un client qui lit aussi les tables du serveur (server-data/) ajoute aux modèles les
-- champs `server`, `classes`, `races`, `minSocket`, `maxSocket` et `stats`, décrits dans
-- docs/BESOINS-CLIENT-SERVEUR.md ; le panneau s'en sert dès qu'ils sont là.
function ACA:HasItemCatalog()
  local ar = _G.ArchRust
  if type(ar) ~= "table" or type(ar.SearchItems) ~= "function" or type(ar.GetItemTemplate) ~= "function"
    or type(ar.GetNumItemTemplates) ~= "function" then
    return false
  end
  local ok, n = pcall(ar.GetNumItemTemplates)
  return ok and (tonumber(n) or 0) > 0
end

-- Modèle d'objet { tid, name, icon, level, category, stack… } ou nil.
function ACA:ItemTemplate(tid)
  tid = tonumber(tid)
  if not tid or tid ~= math.floor(tid) or not self:HasItemCatalog() then return end
  local ok, t = pcall(ArchRust.GetItemTemplate, math.tointeger(tid) or tid)
  if ok and type(t) == "table" then return t end
end

-- Nom d'un objet : catalogue du client, sinon nom appris dans une réponse du serveur.
function ACA:ItemName(tid)
  tid = tonumber(tid)
  if not tid then return end
  local t = self:ItemTemplate(tid)
  return (t and t.name) or self.db.global.itemNames[tid]
end

-- Plus grand TID cherché dans le catalogue (la recherche s'arrête dès que tous les modèles sont vus).
local MAX_ITEM_TID = 1048576

-- Tous les modèles du catalogue, triés par niveau requis puis TID ; lu une fois, à la première
-- recherche. ArchRust.SearchItems plafonne à 5 000 résultats, par TID croissant : le filtre et le tri
-- se font ici, sur l'ensemble. Note au passage ce que le client sait des tables du serveur.
function ACA:ItemIndex()
  if self.itemIndex then return self.itemIndex end
  local index, total = {}, ArchRust.GetNumItemTemplates()
  self.itemServerCount, self.itemDetails = nil, false
  local tid = 0
  while #index < total and tid <= MAX_ITEM_TID do
    local t = ArchRust.GetItemTemplate(tid)
    if t then
      t.stats = nil
      t.search = (t.name or ""):lower()
      index[#index + 1] = t
      if t.server ~= nil then self.itemServerCount = (self.itemServerCount or 0) + (t.server and 1 or 0) end
      if type(t.classes) == "table" then self.itemDetails = true end
    end
    tid = tid + 1
  end
  table.sort(index, function(a, b)
    if (a.level or 0) ~= (b.level or 0) then return (a.level or 0) < (b.level or 0) end
    return a.tid < b.tid
  end)
  self.itemIndex = index
  return index
end

local function contains(list, value)
  for _, v in ipairs(list) do
    if v == value then return true end
  end
  return false
end

-- Bijoux et montures sans restriction se portent par tous ; les armures et armes sans restriction
-- sont l'équipement des monstres et des PNJ, et les consommables ne sont pas réservés à une classe.
local UNIVERSAL_KIND = { [8] = true, [16] = true, [32] = true }

-- L'objet convient-il à `class`, élément de ns.CLASSES ? (Colonnes Race et Class des tables du serveur.)
function ACA:ItemFitsClass(t, class)
  if not class then return true end
  local races, classes = t.races or {}, t.classes or {}
  if #races == 0 and #classes == 0 then return UNIVERSAL_KIND[t.kind] == true end
  return (#races == 0 or contains(races, class.race)) and (#classes == 0 or contains(classes, class.class))
end

-- Noms des classes auxquelles l'objet est réservé ; nil s'il n'est réservé à aucune.
function ACA:ItemClassNames(t)
  if #(t.races or {}) == 0 and #(t.classes or {}) == 0 then return nil end
  local names = {}
  for _, c in ipairs(ns.CLASSES) do
    if self:ItemFitsClass(t, c) then names[#names + 1] = c.name end
  end
  return #names < #ns.CLASSES and #names > 0 and names or nil
end

-- Objets du catalogue, dans l'ordre de ItemIndex : `text` (nom ou début de TID), `category` (nil =
-- toutes), `class` (élément de ns.CLASSES, nil = toutes). Ceux que le serveur n'a pas sont écartés.
function ACA:SearchItems(text, category, class)
  if not self:HasItemCatalog() then return {} end
  local needle = strtrim(text or ""):lower()
  local numeric = needle:match("^%d+$") ~= nil
  local list = {}
  for _, t in ipairs(self:ItemIndex()) do
    if t.server ~= false and (not category or t.category == category)
      and (needle == "" or t.search:find(needle, 1, true) or (numeric and tostring(t.tid):sub(1, #needle) == needle))
      and self:ItemFitsClass(t, class) then
      list[#list + 1] = t
    end
  end
  return list
end

---------------------------------------------------------------------------------------------------
-- Unités
---------------------------------------------------------------------------------------------------

-- Sous ArchRust, UnitIsPlayer n'est vrai que pour soi : les autres personnages se reconnaissent
-- à leur CID, inférieur à 0x40000000 chez ArchCore (PNJ à partir de 0x40000000, monstres de
-- 0x50000000). Le CID termine le GUID (« Player-<cid> », « Unit-<tid>-<cid> »).
local CHARACTER_CID_LIMIT = 0x40000000

local function isCharacterCid(cid)
  return cid ~= nil and cid > 0 and cid < CHARACTER_CID_LIMIT
end

-- Nom du personnage ciblé (pas d'un PNJ ni d'un monstre), ou nil.
function ACA:TargetPlayerName()
  if not UnitExists("target") then return end
  local guid = UnitGUID("target")
  if isCharacterCid(guid and tonumber(guid:match("(%d+)$"))) then return UnitName("target") end
end

-- TID d'un monstre d'après son GUID (« Unit-<tid>-<cid> »), ou nil.
local MONSTER_CID_BASE = 0x50000000
local function monsterTid(guid)
  local tid, cid = (guid or ""):match("^Unit%-(%d+)%-(%d+)$")
  if tid and tonumber(cid) >= MONSTER_CID_BASE then return tonumber(tid) end
end

-- Monstre ciblé : TID et nom, ou nil.
function ACA:TargetMonster()
  if not UnitExists("target") then return end
  local tid = monsterTid(UnitGUID("target"))
  if not tid then return end
  local name = UnitName("target")
  self:LearnMonster(tid, name)
  return tid, name
end

-- Monstres connus du panneau, mémorisés d'une session à l'autre : ceux vus en jeu, ciblés ou simulés.
-- `level` : seulement celui donné par /simloot (ArchRust ne donne pas le niveau des unités).
function ACA:LearnMonster(tid, name, level)
  if not tid or not name or name == "" then return end
  local known = self.db.global.monsters
  local m = known[tid]
  if m and m.name == name and (not level or m.level == level) then return end
  known[tid] = { name = name, level = level or (m and m.level) }
  self:SendMessage("ARCHCOREADMIN_MONSTERS")
end

function ACA:NAME_PLATE_UNIT_ADDED(_, token, guid)
  local tid = monsterTid(guid)
  if tid then self:LearnMonster(tid, UnitName(token)) end
end

-- Liste complète des monstres, si le client la donne (voir docs/BESOINS-CLIENT-SERVEUR.md).
function ACA:MonsterTemplates()
  if self.monsterTemplates == nil then
    local get = _G.ArchRust and ArchRust.GetMonsterTemplates
    local ok, list = pcall(get or error)
    self.monsterTemplates = ok and type(list) == "table" and list or false
  end
  return self.monsterTemplates or nil
end

function ACA:MonsterName(tid)
  tid = tonumber(tid)
  local m = tid and self.db.global.monsters[tid]
  if m then return m.name end
  for _, t in ipairs(self:MonsterTemplates() or {}) do
    if t.tid == tid then return t.name end
  end
end

-- Monstres à proposer, ceux en vue d'abord, puis par nom : { tid, name, level?, inView? }. `text` : une
-- partie du nom ou le début du TID.
function ACA:SearchMonsters(text)
  local inView = {}
  for _, u in ipairs(ArchRust.GetUnits() or {}) do
    local tid = monsterTid(u.guid)
    if tid then
      self:LearnMonster(tid, u.name)
      inView[tid] = true
    end
  end
  local byTid = {}
  for _, t in ipairs(self:MonsterTemplates() or {}) do
    byTid[t.tid] = { tid = t.tid, name = t.name, level = t.level }
  end
  for tid, m in pairs(self.db.global.monsters) do
    local entry = byTid[tid]
    if entry then entry.level = entry.level or m.level
    else byTid[tid] = { tid = tid, name = m.name, level = m.level } end
  end
  local needle = strtrim(text or ""):lower()
  local numeric = needle:match("^%d+$") ~= nil
  local list = {}
  for tid, m in pairs(byTid) do
    if needle == "" or m.name:lower():find(needle, 1, true) or (numeric and tostring(tid):sub(1, #needle) == needle) then
      m.inView = inView[tid]
      list[#list + 1] = m
    end
  end
  table.sort(list, function(a, b)
    if (a.inView or false) ~= (b.inView or false) then return a.inView or false end
    if a.name ~= b.name then return a.name < b.name end
    return a.tid < b.tid
  end)
  return list
end

-- Personnages en vue, sans soi, triés par nom.
function ACA:PlayersInView()
  local me, list = UnitName("player"), {}
  for _, u in ipairs(ArchRust.GetUnits() or {}) do
    if isCharacterCid(u.cid) and u.name and u.name ~= me then
      list[#list + 1] = u.name
    end
  end
  table.sort(list)
  return list
end

---------------------------------------------------------------------------------------------------
-- Commande /aca
---------------------------------------------------------------------------------------------------

function ACA:ApplyBinding()
  local key = self.db.profile.binding
  if self.boundKey and self.boundKey ~= key then ArchRust.SetBinding(self.boundKey, nil) end
  if key and key ~= "" then
    ArchRust.SetBinding(key, function() ACA:Toggle() end)
  end
  self.boundKey = key
end

function ACA:SlashCommand(input)
  local cmd, rest = self:GetArgs(input, 1)
  local args = strtrim(input:sub(rest and rest < 1e9 and rest or #input + 1))
  cmd = cmd and cmd:lower()
  local p = self.db.profile
  if not cmd then
    self:Toggle()
  elseif ns.sectionsByKey[cmd] then
    self:Show(cmd)
  elseif cmd == "probe" or cmd == "niveau" then
    self:ProbeLevel()
  elseif cmd == "bind" then
    -- Chaîne vide plutôt que nil : AceDB remettrait la valeur par défaut.
    p.binding = args:upper()
    self:ApplyBinding()
    self:Print(p.binding ~= "" and format(L["BOUND"], p.binding) or L["UNBOUND"])
  elseif cmd == "confirm" then
    p.confirm = (args ~= "off")
    self:Print(format(L["CONFIRM_STATE"], p.confirm and L["ON"] or L["OFF"]))
  elseif cmd == "replies" then
    p.showReplies = (args ~= "off")
    self:Print(format(L["REPLIES_STATE"], p.showReplies and L["ON"] or L["OFF"]))
  elseif cmd == "launcher" then
    p.launcher = (args ~= "off")
    self:UpdateLauncher()
  elseif cmd == "send" or cmd == "cmd" then
    self:RunFree(args)
  elseif cmd == "reset" then
    self.db:ResetProfile()
    self:ApplyBinding()
    self:UpdateLauncher()
    self:PlaceFrame()
  else
    self:Print(L["HELP"])
  end
end
