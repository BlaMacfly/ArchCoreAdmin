-- Fenêtre principale : en-tête (niveau MJ, cible), onglets, et un bouton lanceur déplaçable.
-- Chaque fichier de Sections/ déclare son onglet avec ns.RegisterSection ; les frames ne sont
-- construites qu'à l'activation de l'AddOn, une fois tous les fichiers chargés.
local addonName, ns = ...
local ACA = LibStub("AceAddon-3.0"):GetAddon("ArchCoreAdmin")
local L = LibStub("AceLocale-3.0"):GetLocale("ArchCoreAdmin")
local W = ns.W

local WIDTH, HEIGHT = 680, 440

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
  f:SetTitle("ArchCore Admin " .. (GetAddOnMetadata(addonName, "Version") or ""))
  makeMovable(f, function() return self.db.profile.framePos end)
  self:PlaceFrame()
  tinsert(UISpecialFrames, "ArchCoreAdminFrame")

  self.levelText = W.Label(f, "", "GameFontHighlightSmall")
  self.levelText:SetPoint("TOPLEFT", f, "TOPLEFT", 12, -8)
  self.targetText = W.Label(f, "", "GameFontHighlightSmall")
  self.targetText:SetPoint("TOPRIGHT", f, "TOPRIGHT", -34, -8)
  self.targetText:SetJustifyH("RIGHT")

  -- Onglets
  local x = 10
  for _, s in ipairs(ns.sections) do
    local tab = W.Button(f, L[s.label], 104, function() self:Show(s.key) end)
    tab:SetPoint("TOPLEFT", f, "TOPLEFT", x, -28)
    s.tab = tab
    x = x + 110

    local page = CreateFrame("Frame", nil, f)
    page:SetPoint("TOPLEFT", f, "TOPLEFT", 12, -58)
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
  for _, other in ipairs(ns.sections) do
    other.page:SetShown(other == s)
    if other == s then other.tab:Disable() else other.tab:Enable() end
  end
  self.frame:Show()
  if s.page.OnShow then s.page:OnShow() end
end

function ACA:Toggle()
  if self.frame:IsShown() then self.frame:Hide() else self:Show() end
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
