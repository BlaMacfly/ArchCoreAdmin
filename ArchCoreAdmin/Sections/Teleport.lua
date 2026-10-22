-- Onglet Téléportation (l'onglet « Tele » d'AzerothAdmin) : /move x,z vers des coordonnées
-- saisies, la position de la cible ou un point enregistré. ArchCore garde l'altitude actuelle
-- (pas encore de carte des hauteurs côté serveur) : seuls x et z comptent.
local addonName, ns = ...
local ACA = LibStub("AceAddon-3.0"):GetAddon("ArchCoreAdmin")
local L = LibStub("AceLocale-3.0"):GetLocale("ArchCoreAdmin")
local W = ns.W

ns.RegisterSection("teleport", "TAB_TELEPORT", function(page)
  local points = ACA.db.global.teleports
  local X = 250

  local list = W.List(page, 236, 18, function(p)
    page.x:SetText(format("%.0f", p.x))
    page.z:SetText(format("%.0f", p.z))
    page.label:SetText(p.name)
  end)
  list:SetPoint("TOPLEFT", page, "TOPLEFT", 0, -18)
  local title = W.Label(page, L["SAVED_POINTS"])
  title:SetPoint("BOTTOMLEFT", list, "TOPLEFT", 2, 3)
  local function refresh()
    table.sort(points, function(a, b) return a.name:lower() < b.name:lower() end)
    list:SetItems(points, function(p) return format("%s  |cff999999(%.0f, %.0f)|r", p.name, p.x, p.z) end)
  end

  local here = W.Label(page, "", "GameFontHighlightSmall")
  here:SetPoint("TOPLEFT", page, "TOPLEFT", X, -18)

  local l = W.Label(page, "X", "GameFontHighlight")
  l:SetPoint("TOPLEFT", page, "TOPLEFT", X, -48)
  page.x = W.Edit(page, 100)
  page.x:SetPoint("TOPLEFT", page, "TOPLEFT", X + 20, -44)
  l = W.Label(page, "Z", "GameFontHighlight")
  l:SetPoint("LEFT", page.x, "RIGHT", 12, 0)
  page.z = W.Edit(page, 100)
  page.z:SetPoint("LEFT", page.x, "RIGHT", 28, 0)

  local function fill(unit)
    local x, _, z = UnitPosition(unit)
    if not x then return false end
    page.x:SetText(format("%.0f", x))
    page.z:SetText(format("%.0f", z))
    return true
  end
  local mine = W.Button(page, L["MY_POSITION"], 130, function() fill("player") end)
  mine:SetPoint("TOPLEFT", page, "TOPLEFT", X, -76)
  local target = W.Button(page, L["TARGET_POSITION"], 150, function()
    if not fill("target") then ACA:Error(L["ERR_NO_TARGET"]) end
  end, L["TIP_TARGET_POSITION"])
  target:SetPoint("LEFT", mine, "RIGHT", 6, 0)

  local go = W.Button(page, L["TELEPORT"], 286, function()
    ACA:Run("move", { { page.x:GetText(), page.z:GetText() } })
  end, L["TIP_MOVE"], "move")
  go:SetPoint("TOPLEFT", page, "TOPLEFT", X, -108)

  l = W.Label(page, L["POINT_NAME"], "GameFontHighlight")
  l:SetPoint("TOPLEFT", page, "TOPLEFT", X, -154)
  page.label = W.Edit(page, 180)
  page.label:SetPoint("TOPLEFT", page, "TOPLEFT", X + 106, -150)
  local save = W.Button(page, L["SAVE_POINT"], 140, function()
    local name = strtrim(page.label:GetText() or "")
    local x, z = tonumber(page.x:GetText()), tonumber(page.z:GetText())
    if name == "" then return ACA:Error(L["ERR_POINT_NAME"]) end
    if not x or not z then return ACA:Error(L["ERR_COORDS"]) end
    for _, p in ipairs(points) do
      if p.name == name then
        p.x, p.z = x, z
        return refresh()
      end
    end
    tinsert(points, { name = name, x = x, z = z })
    refresh()
  end, L["TIP_SAVE_POINT"])
  save:SetPoint("TOPLEFT", page, "TOPLEFT", X, -182)
  local remove = W.Button(page, L["REMOVE"], 100, function()
    if not list.selected then return end
    tremove(points, list.selected)
    list.selected = nil
    refresh()
  end)
  remove:SetPoint("LEFT", save, "RIGHT", 6, 0)

  local note = W.Label(page, L["TELEPORT_NOTE"], "GameFontDisableSmall")
  note:SetPoint("TOPLEFT", page, "TOPLEFT", X, -224)
  note:SetWidth(400)
  note:SetWordWrap(true)

  local acc = 0
  page:SetScript("OnUpdate", function(_, elapsed)
    acc = acc + elapsed
    if acc < 0.25 then return end
    acc = 0
    local x, y, z = UnitPosition("player")
    here:SetText(x and format(L["CURRENT_POSITION"], x, y, z) or "")
  end)
  function page:OnShow()
    if (page.x:GetText() or "") == "" then fill("player") end
    refresh()
  end
end)
