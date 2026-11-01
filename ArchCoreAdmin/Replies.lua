-- Lecture des réponses d'ArchCore. Le serveur répond à chaque commande MJ par un seul message
-- système (en français, voir crates/archcore/src/world/gm.rs) : on le rattache à la plus ancienne
-- commande en attente, puis on en tire ce qui sert au panneau (niveau MJ, taux, noms d'objets…).
-- C'est l'équivalent du crochet sur ChatFrame:AddMessage d'AzerothAdmin.
local addonName, ns = ...
local ACA = LibStub("AceAddon-3.0"):GetAddon("ArchCoreAdmin")
local L = LibStub("AceLocale-3.0"):GetLocale("ArchCoreAdmin")

local REPLY_TIMEOUT = 5

-- « Taux d'expérience », « Taux de butin unique »… → clé de ns.Rates.
local function rateKey(label)
  label = label:gsub("^d'", ""):gsub("^de ", "")
  for _, r in ipairs(ns.Rates) do
    if r.label == label then return r.key end
  end
end

-- Chaque analyseur rend `true` s'il a reconnu le message. `p` est la commande en attente
-- rattachée (ou nil). Un second `true` : ligne qui suit une réponse sur plusieurs lignes (/simloot),
-- traitée comme une réponse même sans commande en attente.
local parsers = {
  function(msg, p)
    local name = msg:match("^Commande inconnue : /(%S+)")
    if not name then return end
    local c = ns.Catalog[name]
    -- ArchCore cache ses commandes aux comptes de niveau 0 : une commande qu'il gère, refusée
    -- ainsi, veut dire « pas de droits MJ ».
    if c and c.archcore then ACA:SetGMLevel(0, true) end
    return true
  end,
  function(msg)
    local req, name, mine = msg:match("^Niveau MJ (%d+) requis pour /(%S+) %(le vôtre : (%d+)%)")
    if not req then return end
    ACA.db.global.levels[name] = tonumber(req)
    ACA:SetGMLevel(tonumber(mine), true)
    return true
  end,
  function(msg, p)
    local name = msg:match("^/(%S+) : .+ Syntaxe : ")
    if not name then return end
    -- La sonde « /SetExp » sans argument : le niveau suffit, seuls les arguments manquent.
    if p and p.probe and ACA.gmLevel == nil then
      ACA:SetGMLevel(ACA:RequiredLevel(name), false)
    end
    return true
  end,
  function(msg)
    local label, value = msg:match("^Taux (.-) réglé à ([%d%.]+)%.$")
    if not label then label, value = msg:match("^Taux (.-) : ([%d%.]+)$") end
    local key = label and rateKey(label)
    if not key then return end
    ACA.rates[key] = tonumber(value)
    ACA:SendMessage("ARCHCOREADMIN_RATES")
    return true
  end,
  function(msg)
    local state = msg:match("^Bonus de discussion : (%S+)$") or msg:match("^Bonus de discussion (%S+)%.$")
    if not state then return end
    ACA.rates.chatBuff = (state == "activé") and 1 or 0
    ACA:SendMessage("ARCHCOREADMIN_RATES")
    return true
  end,
  function(msg)
    -- « 5 × Potion de vie (TID 190) donné(s) à Testeur. » (/create) ou « … ajouté(s) à votre
    -- inventaire. » (/additem) : le nom de l'objet est appris.
    local item, tid = msg:match("^%d+ × (.+) %(TID (%d+)%) ")
    if not item then return end
    ACA.db.global.itemNames[tonumber(tid)] = item
    ACA:SendMessage("ARCHCOREADMIN_ITEMS")
    return true
  end,
  function(msg)
    -- /simloot : « Butin simulé : 500 × Green Worm (TID 450, niveau 1), taux de butin 2.0, taux
    -- d'or 1.0, tueur niveau 50 : 6123 pièce(s) d'or, 39 objet(s) en 2 sorte(s). », puis une ligne
    -- par sorte d'objet (40 au plus, puis une ligne de résumé).
    local kills, monster, tid, level, drop, goldRate, killer, gold, total, kinds = msg:match(
      "^Butin simulé : (%d+) × (.-) %(TID (%d+), niveau (%-?%d+)%), taux de butin ([%d%.]+), taux d'or ([%d%.]+), tueur niveau (%d+) : (%d+) pièce%(s%) d'or, (%d+) objet%(s%) en (%d+) sorte%(s%)%.$")
    if not kills then return end
    kinds = tonumber(kinds)
    ACA.sim = {
      kills = tonumber(kills), monster = monster, tid = tonumber(tid), level = tonumber(level),
      drop = tonumber(drop), goldRate = tonumber(goldRate), killer = tonumber(killer),
      gold = tonumber(gold), total = tonumber(total), kinds = kinds, items = {},
      expected = math.min(kinds, ns.SIMLOOT_LINES) + (kinds > ns.SIMLOOT_LINES and 1 or 0),
    }
    ACA:SendMessage("ARCHCOREADMIN_SIM")
    return true
  end,
  function(msg)
    local sim = ACA.sim
    if not sim or sim.expected <= 0 or msg:sub(1, 3) ~= "· " then return end
    local count, item, tid = msg:match("^· (%d+) × (.+) %(TID (%d+)%)$")
    if count then
      tid = tonumber(tid)
      sim.items[#sim.items + 1] = { tid = tid, count = tonumber(count), name = item }
      -- Nom appris, sauf le nom de remplacement d'un objet inconnu du serveur.
      if item ~= "objet " .. tid then ACA.db.global.itemNames[tid] = item end
    else
      local kinds, n = msg:match("^· … et (%d+) autre%(s%) sorte%(s%), (%d+) objet%(s%)%.$")
      if not kinds then return end
      sim.more = { kinds = tonumber(kinds), count = tonumber(n) }
    end
    sim.expected = sim.expected - 1
    ACA:SendMessage("ARCHCOREADMIN_SIM")
    return true, true
  end,
  function(msg)
    -- « Vitesse de déplacement ×3 (course 3600). »
    local n = msg:match("^Vitesse de déplacement ×(%d+)")
    if not n then return end
    ACA.speed = tonumber(n)
    ACA:SendMessage("ARCHCOREADMIN_STATE")
    return true
  end,
  function(msg)
    -- %a ne reconnaît pas les lettres accentuées (UTF-8) : on compare le début du message.
    local on = msg:find("^Invincibilité activée") ~= nil
    if not on and not msg:find("^Invincibilité désactivée") then return end
    ACA.invincible = on
    ACA:SendMessage("ARCHCOREADMIN_STATE")
    return true
  end,
}

-- Filtre CHAT_MSG_SYSTEM : rend `true` pour masquer le message dans la discussion.
function ACA:OnSystemMessage(msg)
  if type(msg) ~= "string" then return false end
  local now, pending = GetTime(), self.pending
  while pending[1] and now - pending[1].time > REPLY_TIMEOUT do tremove(pending, 1) end
  local p = pending[1]
  local recognized, continued = false, false
  for _, parse in ipairs(parsers) do
    local ok, more = parse(msg, p)
    if ok then
      recognized, continued = true, more == true
      break
    end
  end
  -- Suite d'une réponse sur plusieurs lignes : elle ne consomme pas de commande en attente.
  if continued then
    self:AddLog("<", msg, "simloot")
    return not self.db.profile.showReplies
  end
  -- Un message système sans commande en attente (annonce, autre MJ…) n'est pas à nous, sauf s'il
  -- a la forme d'une réponse MJ.
  if not p and not recognized then return false end
  if p then tremove(pending, 1) end
  if p and p.probe then
    self.probing = nil
    if self.gmLevel == nil then self:SetGMLevel(1, false) end
    self:Print(self:LevelText())
    return true
  end
  self:AddLog("<", msg, p and p.name)
  return p ~= nil and not self.db.profile.showReplies
end

function ACA:LevelText()
  if self.gmLevel == nil then return L["LEVEL_UNKNOWN"] end
  if self.gmLevel == 0 then return L["LEVEL_NONE"] end
  return format(self.gmLevelExact and L["LEVEL_EXACT"] or L["LEVEL_MIN"], self.gmLevel)
end
