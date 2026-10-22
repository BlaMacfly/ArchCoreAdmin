-- Onglet Serveur (l'onglet « Server » d'AzerothAdmin) : taux du serveur (/GetExp, /SetExp…),
-- bonus de discussion, annonce de redémarrage. Les valeurs affichées viennent des réponses du
-- serveur ; les taux changés en jeu reviennent à ceux de world.conf au redémarrage.
local addonName, ns = ...
local ACA = LibStub("AceAddon-3.0"):GetAddon("ArchCoreAdmin")
local L = LibStub("AceLocale-3.0"):GetLocale("ArchCoreAdmin")
local W = ns.W

ns.RegisterSection("server", "TAB_SERVER", function(page)
  local values = {}
  local y = -6
  local header = W.Label(page, L["RATES"])
  header:SetPoint("TOPLEFT", page, "TOPLEFT", 0, y)
  y = y - 24

  for _, r in ipairs(ns.Rates) do
    local label = W.Label(page, L["RATE_" .. r.key], "GameFontHighlight")
    label:SetPoint("TOPLEFT", page, "TOPLEFT", 0, y - 4)
    local value = W.Label(page, "?", "GameFontNormal")
    value:SetPoint("TOPLEFT", page, "TOPLEFT", 150, y - 4)
    values[r.key] = value
    local edit = W.Edit(page, 60)
    edit:SetPoint("TOPLEFT", page, "TOPLEFT", 210, y)
    local read = W.Button(page, L["READ"], 70, function() ACA:Run(r.get) end, nil, r.get)
    read:SetPoint("LEFT", edit, "RIGHT", 6, 0)
    local set = W.Button(page, L["SET"], 70, function() ACA:Run(r.set, { edit:GetText() }) end, L["TIP_RATE"], r.set)
    set:SetPoint("LEFT", read, "RIGHT", 6, 0)
    y = y - 28
  end

  local label = W.Label(page, L["CHAT_BUFF"], "GameFontHighlight")
  label:SetPoint("TOPLEFT", page, "TOPLEFT", 0, y - 4)
  values.chatBuff = W.Label(page, "?", "GameFontNormal")
  values.chatBuff:SetPoint("TOPLEFT", page, "TOPLEFT", 150, y - 4)
  local read = W.Button(page, L["READ"], 70, function() ACA:Run("GetChatBuff") end, nil, "GetChatBuff")
  read:SetPoint("TOPLEFT", page, "TOPLEFT", 210, y)
  local on = W.Button(page, L["ENABLE"], 80, function() ACA:Run("SetChatBuff", { 1 }) end, nil, "SetChatBuff")
  on:SetPoint("LEFT", read, "RIGHT", 6, 0)
  local off = W.Button(page, L["DISABLE"], 80, function() ACA:Run("SetChatBuff", { 0 }) end, nil, "SetChatBuff")
  off:SetPoint("LEFT", on, "RIGHT", 6, 0)
  y = y - 36

  local all = W.Button(page, L["READ_ALL"], 150, function()
    for _, r in ipairs(ns.Rates) do ACA:Run(r.get) end
    ACA:Run("GetChatBuff")
  end, L["TIP_READ_ALL"], "GetExp")
  all:SetPoint("TOPLEFT", page, "TOPLEFT", 210, y)

  -- Annonce de redémarrage, à droite.
  local X = 470
  local restart = W.Label(page, L["RESTART"])
  restart:SetPoint("TOPLEFT", page, "TOPLEFT", X, -6)
  local l = W.Label(page, L["MINUTES"], "GameFontHighlight")
  l:SetPoint("TOPLEFT", page, "TOPLEFT", X, -34)
  local minutes = W.Edit(page, 60)
  minutes:SetPoint("TOPLEFT", page, "TOPLEFT", X + 90, -30)
  minutes:SetText("5")
  l = W.Label(page, L["SECONDS"], "GameFontHighlight")
  l:SetPoint("TOPLEFT", page, "TOPLEFT", X, -64)
  local seconds = W.Edit(page, 60)
  seconds:SetPoint("TOPLEFT", page, "TOPLEFT", X + 90, -60)
  seconds:SetText("0")
  local announce = W.Button(page, L["ANNOUNCE"], 176, function()
    ACA:Run("announce_restart", { minutes:GetText(), seconds:GetText() })
  end, L["TIP_RESTART"], "announce_restart")
  announce:SetPoint("TOPLEFT", page, "TOPLEFT", X, -94)
  local cancel = W.Button(page, L["CANCEL_RESTART"], 176, function()
    ACA:SendLine("/announce_restart 0 0", "announce_restart")
  end, L["TIP_CANCEL_RESTART"], "announce_restart")
  cancel:SetPoint("TOPLEFT", page, "TOPLEFT", X, -122)

  local note = W.Label(page, L["SERVER_NOTE"], "GameFontDisableSmall")
  note:SetPoint("TOPLEFT", page, "TOPLEFT", X, -160)
  note:SetWidth(180)
  note:SetWordWrap(true)

  ACA:RegisterMessage("ARCHCOREADMIN_RATES", function()
    for key, fs in pairs(values) do
      local v = ACA.rates[key]
      if key == "chatBuff" then
        fs:SetText(v == nil and "?" or (v == 1 and L["ON"] or L["OFF"]))
      else
        fs:SetText(v and format("%g", v) or "?")
      end
    end
  end)
end)
