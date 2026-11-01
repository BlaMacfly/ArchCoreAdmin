-- Fenêtre principale : en-tête (niveau MJ, cible), onglets, et un bouton lanceur déplaçable.
-- Chaque fichier de Sections/ déclare son onglet avec ns.RegisterSection ; les frames ne sont
-- construites qu'à l'activation de l'AddOn, une fois tous les fichiers chargés.
local addonName, ns = ...
local ACA = LibStub("AceAddon-3.0"):GetAddon("ArchCoreAdmin")
local L = LibStub("AceLocale-3.0"):GetLocale("ArchCoreAdmin")
local W = ns.W

local WIDTH, HEIGHT = 680, 492
-- Logo (media/logo.png, 512 × 228) affiché en tête à la place du titre.
local LOGO_W, LOGO_H = 168, 75
local HEADER = 80
-- Fenêtre réduite : une barre avec le titre, le bouton de rétablissement et la fermeture.
local MIN_W, MIN_H = 300, 32

ns.sections, ns.sectionsByKey = {}, {}

-- `build(frame)` remplit la page de l'onglet ; `frame:OnShow()` facultatif à l'affichage.
function ns.RegisterSection(key, label, build)
  local s = { key = key, label = label, build = build }
  tinsert(ns.sections, s)
  ns.sectionsByKey[key] = s
end

local function savePosition(frame, pos)
  frame:StopMovingOrSizing()
  pos.x, pos.y = Round(frame:GetLeft()), Round(frame:GetTop() - GetScreenHeight())
end

local function makeMovable(frame, pos)
  frame:EnableMouse(true)
  frame:SetMovable(true)
  frame:SetClampedToScreen(true)
  frame:RegisterForDrag("LeftButton")
  frame:SetScript("OnDragStart", frame.StartMoving)
  frame:SetScript("OnDragStop", function(self) savePosition(self, pos()) end)
end

function ACA:CreateFrames()
  local f = CreateFrame("Frame", "ArchCoreAdminFrame", UIParent, "BasicFrameTemplate")
  self.frame = f
  f:SetSize(WIDTH, HEIGHT)
  f:SetFrameStrata("HIGH")
  makeMovable(f, function() return self.db.profile.framePos end)
  self:PlaceFrame()
  tinsert(UISpecialFrames, "ArchCoreAdminFrame")

  -- Logo à la place du titre ; la version en petit à sa droite.
  local logo = f:CreateTexture(nil, "ARTWORK")
  logo:SetTexture("Interface\\AddOns\\ArchCoreAdmin\\media\\logo")
  logo:SetSize(LOGO_W, LOGO_H)
  logo:SetPoint("TOP", f, "TOP", 0, -3)
  self.logo = logo
  local version = W.Label(f, "v" .. (GetAddOnMetadata(addonName, "Version") or ""), "GameFontDisableSmall")
  version:SetPoint("BOTTOMLEFT", logo, "BOTTOMRIGHT", 2, 6)
  self.version = version

  self.levelText = W.Label(f, "", "GameFontHighlightSmall")
  self.levelText:SetPoint("TOPLEFT", f, "TOPLEFT", 12, -10)
  self.targetText = W.Label(f, "", "GameFontHighlightSmall")
  self.targetText:SetPoint("TOPRIGHT", f, "TOPRIGHT", -60, -10)
  self.targetText:SetJustifyH("RIGHT")

  -- Réduire / rétablir, à gauche de la fermeture ; titre de la barre réduite.
  local minimize = W.Button(f, "-", 22, function() self:SetMinimized(not self.minimized) end)
  minimize:SetPoint("RIGHT", f.CloseButton, "LEFT", -4, 0)
  W.Tooltip(minimize, L["MINIMIZE"], L["TIP_MINIMIZE"])
  self.minimizeButton = minimize
  self.miniTitle = W.Label(f, "", "GameFontNormal")
  self.miniTitle:SetPoint("TOPLEFT", f, "TOPLEFT", 12, -9)
  self.miniTitle:SetWidth(MIN_W - 70)
  self.miniTitle:SetWordWrap(false)
  self.miniTitle:Hide()

  -- Onglets, sur toute la largeur.
  local x = 10
  local step = math.floor((WIDTH - 20 + 6) / #ns.sections)
  for _, s in ipairs(ns.sections) do
    local tab = W.Button(f, L[s.label], step - 6, function() self:Show(s.key) end)
    tab:SetPoint("TOPLEFT", f, "TOPLEFT", x, -HEADER)
    s.tab = tab
    x = x + step

    local page = CreateFrame("Frame", nil, f)
    page:SetPoint("TOPLEFT", f, "TOPLEFT", 12, -HEADER - 30)
    page:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -12, 12)
    page:Hide()
    s.page = page
    s.build(page)
  end

  f:SetScript("OnShow", function() self:RefreshHeader() end)
  self:RegisterMessage("ARCHCOREADMIN_REFRESH", "RefreshHeader")
  f:Hide()

  self:CreateLauncher()
  self:UpdateWidgets()
end

function ACA:PlaceFrame()
  if not self.frame then return end
  local pos = self.db.profile.framePos
  self.frame:ClearAllPoints()
  self.frame:SetPoint("TOPLEFT", UIParent, "TOPLEFT", pos.x, pos.y)
end

function ACA:RefreshHeader()
  if not self.frame then return end
  self.levelText:SetText(self:LevelText())
  local target = self:TargetPlayerName()
  self.targetText:SetText(target and format(L["HEADER_TARGET"], target) or L["HEADER_NO_TARGET"])
end

function ACA:Show(key)
  local s = ns.sectionsByKey[key] or ns.sectionsByKey[self.db.profile.tab] or ns.sections[1]
  self.db.profile.tab = s.key
  -- Ouvrir un onglet rétablit la fenêtre réduite.
  if self.minimized then self:SetMinimized(false, true) end
  for _, other in ipairs(ns.sections) do
    other.page:SetShown(other == s)
    if other == s then other.tab:Disable() else other.tab:Enable() end
  end
  self.frame:Show()
  if s.page.OnShow then s.page:OnShow() end
end

-- Réduit la fenêtre à une barre (titre, rétablir, fermer) sans la fermer : les champs remplis et
-- l'onglet ouvert sont gardés. `noShow` : ne pas réafficher l'onglet (Show s'en charge).
function ACA:SetMinimized(on, noShow)
  local f = self.frame
  self.minimized = on and true or nil
  for _, r in ipairs({ self.logo, self.version, self.levelText, self.targetText }) do r:SetShown(not on) end
  for _, s in ipairs(ns.sections) do
    s.tab:SetShown(not on)
    if on then s.page:Hide() end
  end
  self.miniTitle:SetShown(on)
  self.minimizeButton:SetText(on and "+" or "-")
  self.minimizeButton.tipTitle = on and L["RESTORE"] or L["MINIMIZE"]
  if on then
    local s = ns.sectionsByKey[self.db.profile.tab]
    self.miniTitle:SetText("ArchCore Admin" .. (s and (" — " .. L[s.label]) or ""))
    f:SetSize(MIN_W, MIN_H)
  else
    f:SetSize(WIDTH, HEIGHT)
    if not noShow then self:Show() end
  end
end

-- Lanceur, raccourci, /aca : ouvre, rétablit la fenêtre réduite, ou ferme.
function ACA:Toggle()
  if not self.frame:IsShown() or self.minimized then self:Show() else self.frame:Hide() end
end

---------------------------------------------------------------------------------------------------
-- Lanceur : petit bouton à poser où l'on veut (pas de mini-carte accessible aux AddOns).
---------------------------------------------------------------------------------------------------

function ACA:CreateLauncher()
  local b = CreateFrame("Button", "ArchCoreAdminLauncher", UIParent, "UIPanelButtonTemplate")
  self.launcher = b
  b:SetSize(46, 22)
  b:SetText("MJ")
  b:SetFrameStrata("MEDIUM")
  makeMovable(b, function() return self.db.profile.launcherPos end)
  b:SetScript("OnClick", function() self:Toggle() end)
  W.Tooltip(b, "ArchCore Admin", L["LAUNCHER_TIP"])
  self:UpdateLauncher()
end

function ACA:UpdateLauncher()
  local b = self.launcher
  if not b then return end
  local pos = self.db.profile.launcherPos
  b:ClearAllPoints()
  b:SetPoint("TOPLEFT", UIParent, "TOPLEFT", pos.x, pos.y)
  b:SetShown(self.db.profile.launcher)
end
