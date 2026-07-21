-------------------------------------------------------------
--------------- Core based on "VirtualPlates" ---------------
-------------------------------------------------------------
-- Event-driven engine: plate discovery via NAME_PLATE_UNIT_ADDED (Ascension's
-- retail-like nameplate API, the same one TurboPlates relies on), frame levels
-- assigned once per plate relative to the engine-managed real plate (no per-tick
-- resort), reaction/aggro-color changes detected via UNIT_FACTION/UNIT_THREAT_*
-- scoped to the specific unit (no per-tick poll of every visible plate), and
-- mouseover highlight driven by UPDATE_MOUSEOVER_UNIT (no per-tick UnitName scan).
-- Stacking is handled entirely by Stacking.lua's own driver frame; nothing here
-- calls into it on a timer.

-- Namespace
local AddonFile, RBP = ...

-- API
local select, pairs, ipairs, unpack, string_format, string_sub, GetAddOnMetadata, CreateFrame, UnitLevel, UnitExists, IsInInstance, SetUIVisibility, C_NamePlate =
      select, pairs, ipairs, unpack, string.format, string.sub, GetAddOnMetadata, CreateFrame, UnitLevel, UnitExists, IsInInstance, SetUIVisibility, C_NamePlate

-- Localized namespace definitions
local VirtualPlates = RBP.VirtualPlates
local PlatesVisible = RBP.PlatesVisible
local UpdateCastTextString = RBP.UpdateCastTextString
local UpdateTarget = RBP.UpdateTarget
local SetupRefinedPlate = RBP.SetupRefinedPlate
local ForceLevelHide = RBP.ForceLevelHide
local CheckLDWZoneIndoors = RBP.CheckLDWZoneIndoors
local CheckDominateMind = RBP.CheckDominateMind
local UpdateGroupInfo = RBP.UpdateGroupInfo
local UpdateArenaInfo = RBP.UpdateArenaInfo
local UpdateClassColor = RBP.UpdateClassColor
local UpdateHealthBarColor = RBP.UpdateHealthBarColor
local CheckReactionChange = RBP.CheckReactionChange
local CheckAggroColorChange = RBP.CheckAggroColorChange
local ExecuteClickboxSecureScript = RBP.ExecuteClickboxSecureScript
local InitPlatesClickboxes = RBP.InitPlatesClickboxes
local ClickboxAttributeUpdater = RBP.ClickboxAttributeUpdater
local UpdateClickboxInCombat = RBP.UpdateClickboxInCombat
local UpdateClickboxOutOfCombat = RBP.UpdateClickboxOutOfCombat
local UpdatePlateFlags = RBP.UpdatePlateFlags
local ResetPlateFlags = RBP.ResetPlateFlags
local UpdateRefinedPlate = RBP.UpdateRefinedPlate
local ResetRefinedPlate = RBP.ResetRefinedPlate

-- Local definitions
local EventHandler = CreateFrame("Frame", nil, WorldFrame) -- Main addon frame (event handler + access to native frame methods)
local PlateOverrides = {}	 -- Storage table: [MethodName] = override function for virtual plates

-- Relative frame-level offset for Virtual/healthBar/totemPlate/barlessPlate above
-- Plate's own frame level. Ascension's C_NamePlateManager already keeps the real
-- plates correctly depth-ordered relative to each other, so a fixed per-plate
-- offset (set once, not re-sorted every tick) is sufficient -- the same pattern
-- TurboPlates uses (SetFrameLevel(parent:GetFrameLevel()+N) once, never resorted).
RBP.OVERLAY_FRAMELEVEL_BASE = 10

-- Backup of native frame methods
local WorldFrame_GetChildren = WorldFrame.GetChildren
local SetFrameLevel = EventHandler.SetFrameLevel
local GetParent = EventHandler.GetParent

-- Status Flags
RBP.hasTarget = false
RBP.inCombat = false
RBP.inInstance = false
RBP.inPvEInstance = false
RBP.inPvPInstance = false
RBP.inBG = false
RBP.inArena = false
RBP.inICC = false
RBP.inLDWZone = false
RBP.playerLevel = UnitLevel("player")
RBP.NP_WIDTH = 156.65118520899
RBP.NP_HEIGHT = 39.162796302247

-- Plate handling and updating
do
	local nameplateSizeCheck = true

	local function PlateOnShow(Plate)
		local Virtual = Plate.VirtualPlate
		PlatesVisible[Plate] = Virtual
		-- One-time relative frame-level assignment (re-applied on every show since a
		-- recycled plate frame can get reassigned a new depth by the engine between
		-- shows). No continuous per-tick resort.
		local plateLevel = Plate:GetFrameLevel()
		SetFrameLevel(Virtual, plateLevel + RBP.OVERLAY_FRAMELEVEL_BASE)
		SetFrameLevel(Virtual.healthBar, plateLevel + RBP.OVERLAY_FRAMELEVEL_BASE)
		SetFrameLevel(Virtual.castBar, plateLevel + RBP.OVERLAY_FRAMELEVEL_BASE - 1)
		--- If an anchor attaches to the original plate (by WoW), re-anchor to the Virtual.
		for Index, Region in ipairs(Plate) do
			for Point = 1, Region:GetNumPoints() do
				local point, relativeTo, relativePoint, xOfs, yOfs = Region:GetPoint(Point)
				if relativeTo == Plate then
					Region:SetPoint(point, Virtual, relativePoint, xOfs + RBP.dbp.globalOffsetX + 11, yOfs + RBP.dbp.globalOffsetY)
				end
			end
		end
		UpdatePlateFlags(Plate)
		UpdateRefinedPlate(Plate)
		UpdateTarget(Plate)
		if RBP.inCombat then
			UpdateClickboxInCombat(Plate)
		else
			UpdateClickboxOutOfCombat(Plate)
		end
	end

	local function PlateOnHide(Plate)
		PlatesVisible[Plate] = nil
		ResetPlateFlags(Plate)
		ResetRefinedPlate(Plate)
		if RBP.inCombat then
			ExecuteClickboxSecureScript()
		end
	end

	--- Parents all plate children to the Virtual, and saves references to them in the plate.
	-- @ param Plate  Original nameplate children are being removed from.
	-- @ param ...  Children of Plate to be reparented.
	local function ReparentChildren(Plate, ...)
		local Virtual = Plate.VirtualPlate
		for Index = 1, select("#", ...) do
			local Child = select(Index, ...)
			if Child ~= Virtual then
				local LevelOffset = Child:GetFrameLevel() - Plate:GetFrameLevel()
				Child:SetParent(Virtual)
				Child:SetFrameLevel( Virtual:GetFrameLevel() + LevelOffset) -- Maintain relative frame levels
				Plate[#Plate + 1] = Child;
			end
		end
	end

	--- Parents all plate regions to the Virtual, similar to ReparentChildren.
	-- @ see ReparentChildren
	local function ReparentRegions(Plate, ...)
		local Virtual = Plate.VirtualPlate
		for Index = 1, select("#", ...) do
			local Region = select(Index, ...)
			Region:SetParent(Virtual)
			Plate[#Plate + 1] = Region
		end
	end

	--- Adds and skins a new nameplate.
	-- @ param Plate  Newly found default nameplate to be hooked.
	local function PlateAdd(Plate)
		local Virtual = CreateFrame("Frame", nil, Plate)
		Plate.VirtualPlate = Virtual
		Virtual.RealPlate = Plate
		VirtualPlates[Plate] = Virtual

		if nameplateSizeCheck then
			nameplateSizeCheck = false
			RBP.NP_WIDTH, RBP.NP_HEIGHT = Plate:GetSize()
		end

		Virtual:Hide() -- Gets explicitly shown on plate show
		Virtual:SetPoint("TOP")
		Virtual:SetSize(RBP.NP_WIDTH, RBP.NP_HEIGHT)

		ReparentChildren(Plate, Plate:GetChildren())
		ReparentRegions(Plate, Plate:GetRegions())
		Virtual:SetScale(RBP.dbp.globalScale or 1)
		Virtual:EnableDrawLayer("HIGHLIGHT") -- Allows the highlight to show without enabling mouse events

		Plate:SetScript("OnShow", PlateOnShow)
		Plate:SetScript("OnHide", PlateOnHide)

		-- Hook methods
		for Key, Value in pairs(PlateOverrides) do
			Virtual[Key] = Value
		end

		SetupRefinedPlate(Virtual)

		if Plate:IsVisible() then
			PlateOnShow(Plate)
		end
	end

	--------------------------- Mouseover highlight (event-driven) ---------------------------
	-- Blizzard's native healthBarHighlight region still shows/hides itself automatically
	-- based on real cursor-over-clickbox state; we only need to know WHICH plate that is
	-- (to apply/clear the yellow name-text tint) -- UPDATE_MOUSEOVER_UNIT tells us that
	-- directly, touching at most the previous and new plate instead of scanning all of them.
	local lastHighlightPlate
	local function ApplyMouseoverHighlight()
		if lastHighlightPlate then
			local Virtual = lastHighlightPlate.VirtualPlate
			if Virtual and Virtual.nameTextIsYellow then
				Virtual.newNameText:SetTextColor(Virtual.nameColorR, Virtual.nameColorG, Virtual.nameColorB)
				Virtual.nameTextIsYellow = false
			end
			lastHighlightPlate = nil
		end
		if UnitExists("mouseover") then
			local Plate = C_NamePlate.GetNamePlateForUnit("mouseover")
			if Plate and PlatesVisible[Plate] then
				local Virtual = Plate.VirtualPlate
				if Virtual.isShown and Virtual.healthBarHighlight:IsShown() and not Virtual.nameTextIsYellow then
					Virtual.newNameText:SetTextColor(1, 1, 0)
					Virtual.nameTextIsYellow = true
					if Virtual.castBarIsShown and not Virtual.castText:GetText() then
						UpdateCastTextString(Virtual, "mouseover")
					end
				end
				lastHighlightPlate = Plate
			end
		end
	end

	function EventHandler:UPDATE_MOUSEOVER_UNIT()
		ApplyMouseoverHighlight()
	end

	function EventHandler:NAME_PLATE_UNIT_ADDED(event, unit)
		local Plate = C_NamePlate.GetNamePlateForUnit(unit)
		if not Plate then return end
		Plate.namePlateUnitToken = unit
		if not Plate.VirtualPlate then
			PlateAdd(Plate)
		elseif Plate:IsVisible() and PlatesVisible[Plate] then
			-- Recycled frame reassigned to a (possibly different) unit while already visible.
			UpdatePlateFlags(Plate)
			UpdateRefinedPlate(Plate)
			UpdateTarget(Plate)
		end
	end
	-- NAME_PLATE_UNIT_REMOVED needs no handler: teardown is already driven by Plate's own
	-- OnHide script (PlateOnHide above), which the engine fires reliably on hide/recycle.
end

do
	local Children = {}
	--- Filters the results of WorldFrame:GetChildren to replace plates with their virtuals.
	local function ReplaceChildren(...)
		local Count = select("#", ...)
		for Index = 1, Count do
			local Frame = select(Index, ...)
			Children[Index] = Frame.VirtualPlate or Frame
		end
		for Index = Count + 1, #Children do -- Remove any extras from the last call
			Children[Index] = nil
		end
		return unpack(Children)
	end
	--- Returns Virtual frames in place of real nameplates.
	-- @ return The results of WorldFrame:GetChildren with any reference to a plate replaced with its virtuals.
	function WorldFrame:GetChildren(...)
		return ReplaceChildren(WorldFrame_GetChildren(self, ...))
	end
end

do
	--- Add method overrides to be applied to plates' Virtuals.
	local function AddPlateOverride(MethodName)
		PlateOverrides[MethodName] = function(self, ...)
			local Plate = GetParent(self)
			return Plate[MethodName]( Plate, ... )
		end
	end
	AddPlateOverride("GetParent")
	AddPlateOverride("SetAlpha")
	AddPlateOverride("GetAlpha")
	AddPlateOverride("GetEffectiveAlpha")
end

-- Method overrides to use plates' OnUpdate script handlers instead of their Virtuals' to preserve handler execution order
do
	--- Wrapper for plate OnUpdate scripts to replace their self parameter with the plate's Virtual.
	local function OnUpdateOverride(self, ...)
		self.OnUpdate(self.VirtualPlate, ...)
	end
	local type = type

	local SetScript = EventHandler.SetScript
	--- Redirects all SetScript calls for the OnUpdate handler to the original plate.
	function PlateOverrides:SetScript(Script, Handler, ...)
		if type(Script) == "string" and Script:lower() == "onupdate" then
			local Plate = GetParent(self)
			Plate.OnUpdate = Handler
			return Plate:SetScript(Script, Handler and OnUpdateOverride or nil, ...)
		else
			return SetScript(self, Script, Handler, ...)
		end
	end

	local GetScript = EventHandler.GetScript
	--- Redirects calls to GetScript for the OnUpdate handler to the original plate's script.
	function PlateOverrides:GetScript(Script, ...)
		if type(Script) == "string" and Script:lower() == "onupdate" then
			return GetParent(self).OnUpdate
		else
			return GetScript(self, Script, ...)
		end
	end

	local HookScript = EventHandler.HookScript
	--- Redirects all HookScript calls for the OnUpdate handler to the original plate.
	-- Also passes the virtual to the hook script instead of the plate.
	function PlateOverrides:HookScript (Script, Handler, ...)
		if type(Script) == "string" and Script:lower() == "onupdate" then
			local Plate = GetParent(self)
			if Plate.OnUpdate then
				-- Hook old OnUpdate handler
				local Backup = Plate.OnUpdate;
				function Plate:OnUpdate(...)
					Backup(self, ...) -- Technically we should return Backup's results to match HookScript's hook behavior,
					return Handler(self, ...) -- but the overhead isn't worth it when these results get discarded.
				end
			else
				Plate.OnUpdate = Handler
			end
			return Plate:SetScript(Script, OnUpdateOverride, ...)
		else
			return HookScript(self, Script, Handler, ...)
		end
	end
end

function RBP:OnProfileChanged(...)
	RBP.dbp = self.db.profile
	self:MoveAllShownPlates(RBP.dbp.globalOffsetX - self.globalOffsetX, RBP.dbp.globalOffsetY - self.globalOffsetY)
	self:UpdateProfile()
	self.globalOffsetX = RBP.dbp.globalOffsetX
	self.globalOffsetY = RBP.dbp.globalOffsetY
	if RBP.RefreshStackingConfig then
		RBP.RefreshStackingConfig()
	end
	if RBP.SetStackingEnabled then
		RBP.SetStackingEnabled(RBP.dbp.stackingEnabled)
	end
end

function RBP:Initialize()
	self.db = LibStub("AceDB-3.0"):New("RBPPlacidDB", self.default, true)
	self.db.RegisterCallback(self, "OnProfileChanged", "OnProfileChanged")
	self.db.RegisterCallback(self, "OnProfileCopied", "OnProfileChanged")
	self.db.RegisterCallback(self, "OnProfileReset", "OnProfileChanged")
	self.db.RegisterCallback(self, "OnProfileDeleted", "OnProfileChanged")

	RBP.dbp = self.db.profile -- Replace default profile with AceDB profile
	self.globalOffsetX = RBP.dbp.globalOffsetX
	self.globalOffsetY = RBP.dbp.globalOffsetY

	RBP:BuildBlacklistUI()
	RBP:BuildWhitelistUI()
	ClickboxAttributeUpdater()
	SetUIVisibility(true)

	if RBP.RefreshStackingConfig then
		RBP.RefreshStackingConfig()
	end
	if RBP.SetStackingEnabled then
		RBP.SetStackingEnabled(RBP.dbp.stackingEnabled)
	end

	local config = LibStub("AceConfig-3.0")
	local dialog = LibStub("AceConfigDialog-3.0")
	config:RegisterOptionsTable("RefinedBlizzPlates_ByPlacid", self.MainOptionTable)
	dialog:AddToBlizOptions("RefinedBlizzPlates_ByPlacid", "RefinedBlizzPlates by Placid")
	config:RegisterOptionsTable("RefinedBlizzPlates_ByPlacid_Profiles", LibStub("AceDBOptions-3.0"):GetOptionsTable(self.db))
	dialog:AddToBlizOptions("RefinedBlizzPlates_ByPlacid_Profiles", "Profiles", "RefinedBlizzPlates by Placid")
	config:RegisterOptionsTable("RefinedBlizzPlates_ByPlacid_About", self.AboutTable)
	dialog:AddToBlizOptions("RefinedBlizzPlates_ByPlacid_About", "About", "RefinedBlizzPlates by Placid")
end

--- Initializes settings once loaded.
function EventHandler:ADDON_LOADED(event, Addon)
	if Addon == AddonFile then
		RBP:Initialize()
		print(string_format(" |cffCCCC88RefinedBlizzPlates |cff4b0082by Placid|r v%s", GetAddOnMetadata(AddonFile, "Version")))
		self:UnregisterEvent(event)
		self[event] = nil
	end
end

function EventHandler:PLAYER_LOGIN(event)
	RBP:UpdateTotemDesc()
	RBP:UpdateWorldFrameHeight(true)
	RBP:UpdateCVars()
	self:UnregisterEvent(event)
	self[event] = nil
end

function EventHandler:PLAYER_REGEN_ENABLED()
	RBP.inCombat = false
	if RBP.delayedClickboxUpdate then
		RBP.delayedClickboxUpdate = false
		ClickboxAttributeUpdater()
	end
end

function EventHandler:PLAYER_REGEN_DISABLED()
	RBP.inCombat = true
	InitPlatesClickboxes()
	ExecuteClickboxSecureScript()
end

function EventHandler:PLAYER_TARGET_CHANGED()
	RBP.hasTarget = UnitExists("target") == 1
	for Plate in pairs(PlatesVisible) do
		UpdateTarget(Plate)
	end
end

function EventHandler:PLAYER_ENTERING_WORLD()
	local inInstance, instanceType = IsInInstance()
	RBP.inInstance = inInstance == 1
	RBP.inPvEInstance = instanceType == "party" or instanceType == "raid"
	RBP.inPvPInstance = instanceType == "pvp" or instanceType == "arena"
	RBP.inBG = instanceType == "pvp"
	RBP.inArena = instanceType == "arena"
	UpdateGroupInfo()
	if instanceType == "arena" then
		UpdateArenaInfo()
	end
	if RBP.dbp.LDWfix and instanceType == "raid" then
		RBP:CheckLDWZone()
	end
end

function EventHandler:PARTY_MEMBERS_CHANGED()
	UpdateGroupInfo()
	for Plate in pairs(PlatesVisible) do
		UpdateClassColor(Plate)
		UpdateHealthBarColor(Plate)
	end
end

function EventHandler:PLAYER_PVP_RANK_CHANGED()
	if RBP.dbp.levelText_hide then
		ForceLevelHide()
	end
end

function EventHandler:PLAYER_LEVEL_UP(event, newLevel)
	RBP.playerLevel = newLevel
	if RBP.dbp.levelText_hide then
		ForceLevelHide()
	end
end

function EventHandler:ARENA_OPPONENT_UPDATE(event, unitToken, updateReason)
	if updateReason == "seen" and unitToken:match("^arena(%d+)$") then
		UpdateArenaInfo()
	end
end

function EventHandler:ZONE_CHANGED_INDOORS()
	if RBP.inICC then
		CheckLDWZoneIndoors()
	end
end

function EventHandler:UNIT_AURA(event, unit)
	if RBP.inLDWZone and unit == "player" then
		CheckDominateMind()
	end
end

function EventHandler:RAID_TARGET_UPDATE()
	RBP:UpdateChangedRaidIcons()
end

--- Reaction/hostility can change on a unit without its nameplate being re-added
-- (e.g. a mob becomes attackable). Scoped to the specific unit via its token --
-- replaces the old 200ms poll of every visible plate's bar color.
function EventHandler:UNIT_FACTION(event, unit)
	if not unit or string_sub(unit, 1, 9) ~= "nameplate" then return end
	local Plate = C_NamePlate.GetNamePlateForUnit(unit)
	if Plate and PlatesVisible[Plate] then
		CheckReactionChange(Plate)
	end
end

--- Scoped aggro-color refresh for the specific unit whose threat state changed --
-- replaces the old 200ms poll of every aggro-coloring-enabled plate.
function EventHandler:UNIT_THREAT_SITUATION_UPDATE(event, unit)
	if not unit or string_sub(unit, 1, 9) ~= "nameplate" then return end
	local Plate = C_NamePlate.GetNamePlateForUnit(unit)
	if Plate and PlatesVisible[Plate] then
		CheckAggroColorChange(Plate)
	end
end
EventHandler.UNIT_THREAT_LIST_UPDATE = EventHandler.UNIT_THREAT_SITUATION_UPDATE

--- Global event handler.
function EventHandler:OnEvent(event, ...)
	if self[event] then
		return self[event](self, event, ...)
	end
end

EventHandler:SetScript("OnEvent", EventHandler.OnEvent)
EventHandler:RegisterEvent("ADDON_LOADED")
EventHandler:RegisterEvent("PLAYER_LOGIN")
EventHandler:RegisterEvent("PLAYER_REGEN_DISABLED")
EventHandler:RegisterEvent("PLAYER_REGEN_ENABLED")
EventHandler:RegisterEvent("PLAYER_TARGET_CHANGED")
EventHandler:RegisterEvent("PLAYER_ENTERING_WORLD")
EventHandler:RegisterEvent("PARTY_MEMBERS_CHANGED")
EventHandler:RegisterEvent("PLAYER_PVP_RANK_CHANGED")
EventHandler:RegisterEvent("PLAYER_LEVEL_UP")
EventHandler:RegisterEvent("ARENA_OPPONENT_UPDATE")
EventHandler:RegisterEvent("ZONE_CHANGED_INDOORS")
EventHandler:RegisterEvent("UNIT_AURA")
EventHandler:RegisterEvent("RAID_TARGET_UPDATE")
EventHandler:RegisterEvent("UPDATE_MOUSEOVER_UNIT")
EventHandler:RegisterEvent("UNIT_FACTION")
EventHandler:RegisterEvent("UNIT_THREAT_SITUATION_UPDATE")
EventHandler:RegisterEvent("UNIT_THREAT_LIST_UPDATE")
EventHandler:RegisterEvent("NAME_PLATE_UNIT_ADDED")
RBP.EventHandler = EventHandler
