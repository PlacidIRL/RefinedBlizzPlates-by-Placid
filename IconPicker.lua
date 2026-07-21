-------------------------------------------------------------
--------------------- Icon Picker Popup ----------------------
-------------------------------------------------------------
-- A self-contained "pick an icon like a macro icon" grid popup, used by the
-- Whitelist tab. Built from primitive/standard 3.3.5 frame templates only
-- (no reliance on newer convenience templates that may not exist on this
-- client) so it doesn't depend on anything besides base FrameXML.

local AddonFile, RBP = ...

local CreateFrame, ipairs, math_ceil, math_max, math_floor, string_find, string_lower =
      CreateFrame, ipairs, math.ceil, math.max, math.floor, string.find, string.lower

local ASSETS = "Interface\\AddOns\\" .. AddonFile .. "\\Assets\\"

------------------------- Icon catalog -------------------------
local IconCatalog = {}
local seenPaths = {}
local function AddIcon(name, path)
	if not path or path == "" or seenPaths[path] then return end
	seenPaths[path] = true
	IconCatalog[#IconCatalog + 1] = { name = name, icon = path }
end

-- RBP's own shipped icons -- known-good (already used by the Blacklist/Totem features).
AddIcon("Alliance Battle Standard", ASSETS .. "Icons\\Alliance_Battle_Standard")
AddIcon("Horde Battle Standard", ASSETS .. "Icons\\Horde_Battle_Standard")
AddIcon("Ebon Gargoyle", ASSETS .. "Icons\\Ebon_Gargoyle")
AddIcon("Shadowfiend", ASSETS .. "Icons\\Shadowfiend")
AddIcon("Spirit Wolf", ASSETS .. "Icons\\Spirit_Wolf")
AddIcon("Treant", ASSETS .. "Icons\\Treant")
AddIcon("Venomous Snake", ASSETS .. "Icons\\Venomous_Snake")
AddIcon("Viper", ASSETS .. "Icons\\Viper")
AddIcon("Water Elemental", ASSETS .. "Icons\\Water_Elemental")

-- Raid target markers (individual textures, distinct from the SetRaidTargetIconTexture atlas).
AddIcon("Raid Icon: Star", "Interface\\TargetingFrame\\UI-RaidTargetingIcon_1")
AddIcon("Raid Icon: Circle", "Interface\\TargetingFrame\\UI-RaidTargetingIcon_2")
AddIcon("Raid Icon: Diamond", "Interface\\TargetingFrame\\UI-RaidTargetingIcon_3")
AddIcon("Raid Icon: Triangle", "Interface\\TargetingFrame\\UI-RaidTargetingIcon_4")
AddIcon("Raid Icon: Moon", "Interface\\TargetingFrame\\UI-RaidTargetingIcon_5")
AddIcon("Raid Icon: Square", "Interface\\TargetingFrame\\UI-RaidTargetingIcon_6")
AddIcon("Raid Icon: Cross", "Interface\\TargetingFrame\\UI-RaidTargetingIcon_7")
AddIcon("Raid Icon: Skull", "Interface\\TargetingFrame\\UI-RaidTargetingIcon_8")

-- Generic "mark a unit" icons.
local MiscIcons = {
	"INV_Misc_QuestionMark", "INV_Misc_Note_01", "INV_Misc_Note_02", "INV_Misc_Book_09",
	"INV_Misc_Bell_01", "INV_Misc_Gear_01", "INV_Misc_Gear_02", "INV_Misc_Key_03",
	"INV_Misc_Key_11", "INV_Misc_Coin_01", "INV_Misc_Coin_02", "INV_Misc_Coin_17",
	"INV_Misc_Bag_08", "INV_Misc_Bag_10", "INV_Misc_Chest_Undead", "INV_Misc_Bone_01",
	"INV_Misc_Bone_04", "INV_Misc_Horn_01", "INV_Misc_Eye_01", "INV_Misc_Eye_02",
	"INV_Misc_Head_Dragon_01", "INV_Misc_Head_Dragon_Blue", "INV_Misc_Head_Dragon_Green",
	"INV_Misc_Head_Dragon_Black", "INV_Misc_Head_Dragon_Red", "INV_Misc_Head_Human_01",
	"INV_Misc_Head_Orc_01", "INV_Misc_Head_Undead_01", "INV_Misc_Skull_01", "INV_Misc_Skull_02",
	"INV_Misc_Skull_03", "INV_Misc_Skull_Elf_01", "INV_Misc_Skull_Human_01", "INV_Misc_Skull_Orc_01",
	"INV_Misc_Gem_01", "INV_Misc_Gem_Amethyst_01", "INV_Misc_Gem_Emerald_01", "INV_Misc_Gem_Opal_01",
	"INV_Misc_Gem_Pearl_01", "INV_Misc_Gem_Ruby_01", "INV_Misc_Gem_Sapphire_01", "INV_Misc_Gem_Topaz_01",
	"INV_Misc_Flag_01", "INV_Misc_Flag_02", "INV_Misc_Rune_01",
	"INV_Misc_Food_01", "INV_Misc_PocketWatch_01", "INV_Misc_Spyglass_02", "INV_Misc_Map_01",
	"INV_Misc_Map_02", "INV_Misc_Lockpick_01", "INV_Misc_Ammo_Bullet_01", "INV_Misc_Ammo_Arrow_01",
}
for _, tex in ipairs(MiscIcons) do
	AddIcon(tex, "Interface\\Icons\\" .. tex)
end

-- Class/ability icons -- one flagship, long-stable icon per common ability.
local AbilityIcons = {
	"Ability_Warrior_Charge", "Ability_Warrior_Revenge", "Ability_Warrior_BattleShout",
	"Ability_Rogue_Stealth", "Ability_Rogue_Eviscerate", "Ability_Rogue_KidneyShot",
	"Ability_Hunter_MarkedForDeath", "Ability_Hunter_AimedShot", "Ability_Hunter_BeastCall",
	"Ability_Druid_Bear", "Ability_Druid_CatForm", "Ability_Druid_TravelForm",
	"Ability_Paladin_BlessingOfMight", "Ability_Paladin_HammerOfWrath", "Ability_Paladin_DivineStorm",
	"Ability_Deathknight_DarkConviction", "Ability_Deathknight_IcyTouch", "Ability_Deathknight_DeathStrike",
	"Ability_Creature_Cursed_02", "Ability_Creature_Poison_06", "Ability_Marksmanship",
	"Ability_ThunderBolt", "Ability_GolemThunderClap", "Ability_Racial_Avatar",
	"Spell_Nature_Lightning", "Spell_Nature_LightningBolt02", "Spell_Nature_HealingTouch",
	"Spell_Nature_StarFall", "Spell_Fire_Fireball02", "Spell_Fire_FlameBolt",
	"Spell_Frost_FrostBolt02", "Spell_Frost_ChainsOfIce", "Spell_Shadow_ShadowBolt",
	"Spell_Shadow_DeathCoil", "Spell_Shadow_Requiem", "Spell_Holy_HolyBolt",
	"Spell_Holy_FlashHeal", "Spell_Holy_PowerWordShield", "Spell_Holy_GreaterHeal",
	"Spell_Arcane_Blast", "Spell_Arcane_PortalStormwind", "Spell_Magic_LesserInvisibilty",
}
for _, tex in ipairs(AbilityIcons) do
	AddIcon(tex, "Interface\\Icons\\" .. tex)
end

-- PvP / achievement flavored icons.
local PvPIcons = {
	"Achievement_PVP_A_A", "Achievement_PVP_H_H", "Achievement_BG_winWSG",
	"Achievement_BG_winAB", "Achievement_BG_winAV", "Achievement_BG_winEOTS",
	"INV_BannerPVP_02", "INV_Jewelry_Talisman_04", "Achievement_Character_Human_Female",
	"Achievement_Character_Orc_Male",
}
for _, tex in ipairs(PvPIcons) do
	AddIcon(tex, "Interface\\Icons\\" .. tex)
end

-- Creature/boss/environmental flavor icons -- useful for marking non-player units.
local CreatureIcons = {
	"Ability_Creature_Cursed_01", "Ability_Creature_Cursed_03", "Ability_Creature_Cursed_04",
	"Ability_Creature_Disease_01", "Ability_Creature_Disease_02", "Ability_Creature_Disease_03",
	"Ability_Creature_Poison_01", "Ability_Creature_Poison_02", "Ability_Creature_Poison_03",
	"Spell_Shadow_RaiseDead", "Spell_Shadow_SummonFelHunter", "Spell_Shadow_SummonImp",
	"Spell_Shadow_SummonVoidWalker", "Spell_Shadow_AnimateDead", "Spell_Nature_Regenerate",
	"Ability_Mount_Nightmarehorse", "Ability_Mount_RidingHorse", "INV_Misc_MonsterClaw_04",
	"INV_Misc_MonsterScales_03", "INV_Misc_MonsterScales_07", "INV_Misc_MonsterFang_01",
	"INV_Misc_Fang_02", "INV_Misc_Bone_05", "INV_Misc_Bone_08",
}
for _, tex in ipairs(CreatureIcons) do
	AddIcon(tex, "Interface\\Icons\\" .. tex)
end

-- More generic markers / quest-flavored icons.
local MoreMiscIcons = {
	"INV_Misc_QuestionMark", "INV_Misc_Punchcards", "INV_Misc_Ticket_Tarot_Blessings",
	"INV_Misc_Ticket_Tarot_Curses", "INV_Misc_Ticket_Tarot_Fortune", "INV_Misc_Wrench_01",
	"INV_Misc_Wrench_02", "INV_Misc_Hammer_01", "INV_Misc_Hammer_04",
	"INV_Misc_Axe_02", "INV_Misc_Axe_04", "INV_Misc_Bandage_08",
	"INV_Misc_Bandage_15", "INV_Misc_Cape_10", "INV_Misc_Cape_13",
	"INV_Misc_Fish_02", "INV_Misc_Fish_09", "INV_Misc_Herb_01",
	"INV_Misc_Herb_02", "INV_Misc_Idol_02", "INV_Misc_Idol_03",
	"INV_Misc_Orb_01", "INV_Misc_Orb_02", "INV_Misc_Orb_03",
	"INV_Misc_PurpleShardTriangle", "INV_Misc_QirajiCrystal_01", "INV_Misc_Statue_02",
	"INV_Misc_Sword_04", "INV_Misc_Wand_01", "INV_Jewelry_Ring_03",
	"INV_Jewelry_Necklace_02",
}
for _, tex in ipairs(MoreMiscIcons) do
	AddIcon(tex, "Interface\\Icons\\" .. tex)
end

-- Snapshot of the hand-curated set, taken before the spellbook (below) gets merged into
-- IconCatalog -- this fixed snapshot is the small "quick pick" popup's catalog, while
-- IconCatalog (curated + spellbook) is the "Load More Icons..." popup's catalog.
local CuratedCatalog = {}
for i, entry in ipairs(IconCatalog) do
	CuratedCatalog[i] = entry
end

------------------------- Dynamic sources -------------------------
-- Pulled live from the game client, so these are always guaranteed-valid icons
-- (no risk of a hand-typed texture path being wrong) -- and naturally scale with
-- how many spells the character has learned, which is usually a lot by max level.
local function PopulateSpellbookIcons()
	local GetTexture = GetSpellTexture or GetSpellBookItemTexture
	local GetName = GetSpellName or GetSpellBookItemName
	if not (GetTexture and GetName and GetNumSpellTabs and GetSpellTabInfo) then return end
	local numTabs = GetNumSpellTabs()
	for tab = 1, numTabs do
		local tabName, _, offset, numSpells = GetSpellTabInfo(tab)
		if offset and numSpells then
			for i = offset + 1, offset + numSpells do
				local texture = GetTexture(i, BOOKTYPE_SPELL)
				local name = GetName(i, BOOKTYPE_SPELL)
				if texture and name and name ~= "" then
					AddIcon(name, texture)
				end
			end
		end
	end
end

------------------------- Popup frame (shared, virtualized grid) -------------------------
-- A well-leveled character's spellbook alone can add well over a hundred icons on top
-- of the curated set, so the grid is virtualized: a small fixed pool of buttons is
-- recycled based on scroll position instead of creating/repositioning one frame per
-- catalog entry. Filtering (search) only rebuilds a lightweight `filtered` index list,
-- not any frames. (Also leaves headroom if more icons get added to the catalog later.)
--
-- Two windows share this builder: a small "quick pick" (curated set only, opens by
-- default) and a large one (everything), reached via the small window's "Load More
-- Icons..." button so browsing the full library is opt-in rather than the default.
local BUTTON_SIZE = 34
local BUTTON_PAD = 4
local STEP = BUTTON_SIZE + BUTTON_PAD
local BUFFER_ROWS = 3

-- Shared across both windows so a callback handed to the small picker still works after
-- "Load More Icons..." hands off to the big one (RBP.OpenIconPicker is the only place
-- that sets this to a new value; the hand-off itself passes nil to keep it as-is).
local activeOnSelect

local function CreatePickerWindow(opts)
	local columns = opts.columns
	local poolSize = (opts.visibleRows + BUFFER_ROWS * 2) * columns

	local win = {}
	local picker, scrollFrame, scrollChild, searchBox
	local pool = {}
	local filtered = {}
	local spellbookPopulated = false

	local function UpdateVisibleWindow()
		local scrollOffset = scrollFrame:GetVerticalScroll()
		local firstRow = math_max(0, math_floor(scrollOffset / STEP) - BUFFER_ROWS)
		local firstIndex = firstRow * columns + 1

		for p = 1, poolSize do
			local button = pool[p]
			local entry = filtered[firstIndex + p - 1]
			if entry then
				local pos = firstIndex + p - 2 -- zero-based position in the filtered list
				local col = pos % columns
				local row = math_floor(pos / columns)
				button.entry = entry
				button.icon:SetTexture(entry.icon)
				button:ClearAllPoints()
				button:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", col * STEP, -row * STEP)
				button:Show()
			else
				button.entry = nil
				button:Hide()
			end
		end
	end

	local function RelayoutIcons()
		local search = searchBox:GetText()
		search = search ~= "" and string_lower(search) or nil

		for i = #filtered, 1, -1 do
			filtered[i] = nil
		end
		local count = 0
		for _, entry in ipairs(opts.catalog) do
			if not search or string_find(string_lower(entry.name), search, 1, true) then
				count = count + 1
				filtered[count] = entry
			end
		end

		local rows = math_max(1, math_ceil(count / columns))
		scrollChild:SetHeight(rows * STEP)
		-- A new search can otherwise leave the view scrolled past the (now shorter) results.
		scrollFrame:SetVerticalScroll(0)
		UpdateVisibleWindow()
	end

	local function CreateIconButton()
		local button = CreateFrame("Button", nil, scrollChild)
		button:SetSize(BUTTON_SIZE, BUTTON_SIZE)
		local tex = button:CreateTexture(nil, "ARTWORK")
		tex:SetAllPoints()
		button.icon = tex
		local highlight = button:CreateTexture(nil, "HIGHLIGHT")
		highlight:SetAllPoints()
		highlight:SetTexture("Interface\\Buttons\\ButtonHilight-Square")
		highlight:SetBlendMode("ADD")
		button:SetScript("OnEnter", function(self)
			if not self.entry then return end
			GameTooltip:SetOwner(self, "ANCHOR_TOPRIGHT")
			GameTooltip:SetText(self.entry.name)
			GameTooltip:Show()
		end)
		button:SetScript("OnLeave", function() GameTooltip:Hide() end)
		button:SetScript("OnClick", function(self)
			if self.entry and activeOnSelect then activeOnSelect(self.entry.icon) end
			picker:Hide()
		end)
		button:Hide()
		return button
	end

	local function EnsurePicker()
		if picker then return end

		picker = CreateFrame("Frame", opts.frameName, UIParent)
		picker:SetSize(opts.width, opts.height)
		picker:SetPoint("CENTER")
		picker:SetFrameStrata("DIALOG")
		picker:SetToplevel(true)
		picker:SetMovable(true)
		picker:EnableMouse(true)
		picker:SetClampedToScreen(true)
		picker:Hide()
		picker:SetBackdrop({
			bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
			edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
			tile = true, tileSize = 32, edgeSize = 32,
			insets = { left = 11, right = 12, top = 12, bottom = 11 },
		})

		local title = picker:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
		title:SetPoint("TOP", 0, -16)
		title:SetText(opts.title)

		picker:RegisterForDrag("LeftButton")
		picker:SetScript("OnDragStart", picker.StartMoving)
		picker:SetScript("OnDragStop", picker.StopMovingOrSizing)

		local closeButton = CreateFrame("Button", nil, picker, "UIPanelCloseButton")
		closeButton:SetPoint("TOPRIGHT", -4, -4)
		closeButton:SetScript("OnClick", function() picker:Hide() end)

		searchBox = CreateFrame("EditBox", nil, picker, "InputBoxTemplate")
		searchBox:SetSize(opts.width - 80, 20)
		searchBox:SetPoint("TOP", 0, -40)
		searchBox:SetAutoFocus(false)
		searchBox:SetScript("OnTextChanged", RelayoutIcons)
		searchBox:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)

		local scrollBottomInset = opts.onLoadMore and 46 or 16
		scrollFrame = CreateFrame("ScrollFrame", opts.frameName .. "Scroll", picker, "UIPanelScrollFrameTemplate")
		scrollFrame:SetPoint("TOPLEFT", 16, -66)
		scrollFrame:SetPoint("BOTTOMRIGHT", -34, scrollBottomInset)
		-- HookScript (not SetScript) so the template's own scrollbar-thumb sync keeps working;
		-- this only adds the pool-recycling on top of it.
		scrollFrame:HookScript("OnVerticalScroll", UpdateVisibleWindow)
		scrollFrame:EnableMouseWheel(true)
		scrollFrame:SetScript("OnMouseWheel", function(self, delta)
			local maxScroll = self:GetVerticalScrollRange()
			local newScroll = self:GetVerticalScroll() - delta * STEP * 3
			if newScroll < 0 then newScroll = 0 end
			if maxScroll and newScroll > maxScroll then newScroll = maxScroll end
			self:SetVerticalScroll(newScroll)
		end)

		scrollChild = CreateFrame("Frame", nil, scrollFrame)
		scrollChild:SetWidth(columns * STEP)
		scrollChild:SetHeight(1)
		scrollFrame:SetScrollChild(scrollChild)

		for p = 1, poolSize do
			pool[p] = CreateIconButton()
		end

		if opts.onLoadMore then
			local loadMoreButton = CreateFrame("Button", nil, picker, "UIPanelButtonTemplate")
			loadMoreButton:SetSize(opts.width - 32, 22)
			loadMoreButton:SetPoint("BOTTOM", 0, 14)
			loadMoreButton:SetText(opts.loadMoreText or "Load More Icons...")
			loadMoreButton:SetScript("OnClick", function()
				opts.onLoadMore(searchBox:GetText())
			end)
		end

		RelayoutIcons()
	end

	--- Opens this picker window. Pass a new onSelectCallback to (re)bind it, or nil to
	-- keep whatever callback is already active (used by the small->big hand-off).
	function win.Open(onSelectCallback, initialSearch)
		EnsurePicker()
		if onSelectCallback then
			activeOnSelect = onSelectCallback
		end
		if opts.populateSpellbook and not spellbookPopulated then
			spellbookPopulated = true
			-- Deferred to first-open (well after login) so the player's spellbook is
			-- fully populated; adds every icon the character currently knows.
			PopulateSpellbookIcons()
		end
		searchBox:SetText(initialSearch or "")
		searchBox:ClearFocus()
		RelayoutIcons()
		picker:Show()
	end

	function win.Hide()
		if picker then picker:Hide() end
	end

	return win
end

-- Forward-declared: the `onLoadMore` closure below captures SmallPicker as an upvalue,
-- but `local SmallPicker = CreatePickerWindow({...})` would evaluate that whole table
-- (closure included) BEFORE the assignment happens, so the closure would otherwise
-- capture a global (nil) instead of this local. Declaring it first fixes that -- the
-- closure only needs the value once it's actually clicked, not at creation time.
local SmallPicker

local BigPicker = CreatePickerWindow({
	frameName = "RBPPlacidIconPickerBig",
	title = "Choose an icon (full library)",
	width = 440,
	height = 460,
	columns = 10,
	visibleRows = 10,
	catalog = IconCatalog,
	populateSpellbook = true,
})

SmallPicker = CreatePickerWindow({
	frameName = "RBPPlacidIconPicker",
	title = "Choose an icon",
	width = 320,
	height = 380,
	columns = 7,
	visibleRows = 7,
	catalog = CuratedCatalog,
	-- Not a dynamic count: the only extra source now is the spellbook, which isn't
	-- populated until the big picker's first open, so a count here would misleadingly
	-- read "(0 more)" every time.
	loadMoreText = "Load More Icons...",
	onLoadMore = function(currentSearch)
		SmallPicker.Hide()
		BigPicker.Open(nil, currentSearch)
	end,
})

--- Opens the icon picker: a small curated quick-pick by default, with a "Load More
-- Icons..." button that opens the full library (curated set + your spellbook) in a
-- larger window. onSelectCallback(iconPath) is invoked when the user clicks an icon
-- in either window.
function RBP.OpenIconPicker(currentIcon, onSelectCallback)
	SmallPicker.Open(onSelectCallback)
end
