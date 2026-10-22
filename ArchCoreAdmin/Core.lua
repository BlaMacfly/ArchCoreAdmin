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
  global = { teleports = {}, items = {}, itemNames = {}, levels = {} },
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
  self:RegisterChatCommand("aca", "SlashCommand")
  self:RegisterChatCommand("archcoreadmin", "SlashCommand")
end

function ACA:OnEnable()
  self:RegisterEvent("PLAYER_ENTERING_WORLD")
  self:RegisterEvent("PLAYER_TARGET_CHANGED", "UpdateWidgets")
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
function ACA:ProbeLevel()
  self.probing = true
  self:SetGMLevel(nil, nil)
  self:SendLine("/SetExp", "SetExp", { probe = true })
  self:ScheduleTimer(function()
    if self.probing then
      self.probing = nil
      self:Print(L["PROBE_NO_REPLY"])
      self:UpdateWidgets()
    end
  end, REPLY_TIMEOUT)
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
  tinsert(self.pending, { name = name, line = line, time = GetTime(), probe = opts.probe })
  if not opts.probe then self:AddLog(">", line, name) end
  RunMacroText(line)
  self:SendMessage("ARCHCOREADMIN_SENT", name, line)
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
