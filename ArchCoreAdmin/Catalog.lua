-- Catalogue des commandes MJ, recopié de la table `COMMANDS` d'ArchCore
-- (crates/archcore/src/world/gm.rs) : nom (la casse compte), niveau MJ par défaut, arguments.
-- Le serveur reste seul juge : le niveau d'une commande se change dans `world.conf`
-- (GM.CommandLevel.<nom>) et l'AddOn apprend le vrai niveau dans les réponses du serveur.
--
-- Types d'argument : "name" (nom entre guillemets), "int", "float", "coords" (x,z).
-- `opt = true` : argument facultatif. `confirm` : demande une confirmation avant l'envoi.
-- `archcore = false` : commande du panneau d'Archonia qu'ArchCore ne gère pas encore
-- (elle répond « Commande inconnue ») ; affichée en gris dans l'onglet MJ.
local addonName, ns = ...

local C = {}
ns.Catalog = C

local function def(name, level, args, extra)
  local c = { name = name, level = level, args = args or {} }
  for k, v in pairs(extra or {}) do c[k] = v end
  if c.archcore == nil then c.archcore = true end
  C[#C + 1] = c
  C[name] = c
  return c
end

local NAME, NAME_OPT = { "name" }, { "name", opt = true }
local INT, INT_OPT = { "int" }, { "int", opt = true }
local FLOAT = { "float" }

-- Taux du serveur : (clé de réponse, commande Set, commande Get).
ns.Rates = {
  { key = "exp", label = "expérience", set = "SetExp", get = "GetExp" },
  { key = "gold", label = "or", set = "SetGold", get = "GetGold" },
  { key = "drop", label = "butin", set = "SetDrop", get = "GetDrop" },
  { key = "uniqueDrop", label = "butin unique", set = "SetUniqueDrop", get = "GetUniqueDrop" },
  { key = "charisma", label = "charisme", set = "SetCharisma", get = "GetCharisma" },
  { key = "prestige", label = "prestige", set = "SetPrestigeRate", get = "GetPrestigeRate" },
}
for _, r in ipairs(ns.Rates) do
  def(r.set, 3, { FLOAT }, { section = "server" })
  def(r.get, 1, {}, { section = "server", silent = true })
end
def("SetChatBuff", 3, { INT }, { section = "server" })
def("GetChatBuff", 1, {}, { section = "server", silent = true })

def("chatban", 1, { NAME, INT }, { section = "players", confirm = true })
def("kill", 2, { NAME_OPT }, { section = "players", confirm = true })
def("invincible", 2, { INT_OPT }, { section = "gm" })
def("rename_char", 2, { NAME, NAME }, { section = "players", confirm = true })
def("create", 3, { NAME, INT, INT_OPT, INT_OPT }, { section = "items" })
def("additem", 3, { INT, INT_OPT }, { section = "items" })
def("speed", 2, { INT }, { section = "gm" })
def("questreset", 3, { INT }, { section = "gm" })
def("recast", 3, {}, { section = "gm" })
def("level", 3, { INT, NAME_OPT }, { section = "players", confirm = true })
def("money", 3, { INT, NAME_OPT }, { section = "players" })
def("announce_restart", 3, { INT, INT_OPT }, { section = "server", confirm = true })
def("move", 1, { { "coords" } }, { section = "teleport" })

-- Commandes d'Archonia sans équivalent dans ArchCore pour l'instant (page « Administration »
-- du wiki d'ArchCore). Elles sont envoyées telles quelles depuis la commande libre.
for _, usage in ipairs({
  '/kill_explosion <effet> "nom"', '/arena_ban_day "nom" <jours>', '/arena_ban_hour "nom" <heures>',
  '/spectate_arena "nom"', '/leave_spectate', '/tournament round', '/tournament disable',
  '/death_match freeze', '/racewar reload', '/game_event set_only_solo', '/counter open "nom" <secondes>',
  '/battlepass reload', '/reload_events', '/enable_events', '/disable_events', '/go_rift "nom"',
  '/close_rift', '/next_rift_objectives', '/bg_off', '/spawn_instance "nom" <nombre> <rayon>',
  '/refresh_lua_scripts', '/reload_ip_players', '/log_activity', '/cast_cap <0-100>',
  '/cooldown_cap <0-100>', '/last_refine', '/refresh_prestige_db',
}) do
  local name = usage:match("^/(%S+)")
  if not C[name] then def(name, 1, nil, { archcore = false, usage = usage }) end
end

-- Syntaxe affichée (« /create "nom" <TID> [quantité] [0|1] »).
local SHOW = { name = '"nom"', int = "<n>", float = "<x>", coords = "x,z" }
for _, c in ipairs(C) do
  if not c.usage then
    local parts = { "/" .. c.name }
    for _, a in ipairs(c.args) do
      local s = SHOW[a[1]]
      parts[#parts + 1] = a.opt and ("[" .. s .. "]") or s
    end
    c.usage = table.concat(parts, " ")
  end
end
