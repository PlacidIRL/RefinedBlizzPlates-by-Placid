-------------------------------------------------------------
------------------ Spring-physics stacking -------------------
-------------------------------------------------------------
-- Replaces the classic exponential-relaxation stacking loop with a
-- TurboPlates-style split: an O(n^2) layout pass that only recomputes
-- target offsets when something actually moved (throttled + dirty-gated),
-- and a cheap O(n) implicit-spring animation pass that runs every frame
-- for smooth motion regardless of how often layout recomputes.
--
-- Applied through RBP's existing SetClampedToScreen/SetClampRectInsets
-- mechanism, same as the classic implementation, so nothing else in the
-- addon needs to know the offset is spring-driven instead of decay-driven.

local AddonFile, RBP = ... -- namespace

----------------------------- API -----------------------------
local pairs, select, sort, GetTime, CreateFrame, math_abs, math_min =
      pairs, select, sort, GetTime, CreateFrame, math.abs, math.min

------------------------- Storage -------------------------
-- [Plate] = { xpos, ypos, position, velocity, targetOffset, prevX, prevY, isSettled, lastClampBottom }
-- Populated/cleared by Functions.lua (UpdateRefinedPlate / ResetRefinedPlate), same as the classic implementation.
RBP.StackablePlates = {}
local StackablePlates = RBP.StackablePlates

------------------------- Presets -------------------------
RBP.StackingPresets = {
	Balanced = { springFrequencyRaise = 10, springFrequencyLower = 10, launchDamping = 0.8, settleThreshold = 0.9, maxPlates = 60 },
	Chill    = { springFrequencyRaise = 7,  springFrequencyLower = 6,  launchDamping = 0.6, settleThreshold = 0.9, maxPlates = 60 },
	Snappy   = { springFrequencyRaise = 13, springFrequencyLower = 11, launchDamping = 0.9, settleThreshold = 1,   maxPlates = 60 },
}

------------------------- Cached config (refreshed by RefreshStackingConfig) -------------------------
local omegaRaise, omegaLower, launchDamping, launchDampingComplement, settleThreshold, maxPlates = 10, 10, 0.8, 0.2, 0.9, 60
local xspace, yspace, originpos = 130, 15, 0

local INV_DIST_THRESHOLD = 1 / 20 -- launch-damping ramp completes within 20px of target
local SETTLE_VELOCITY = 0.4
local MAX_DT = 0.05
local LAYOUT_INTERVAL = 0.03 -- ~33 layout passes/sec cap; dirty-gate below skips most of them anyway
local POSITION_DIRTY_THRESHOLD = 3 -- px

--- Re-reads settings into the cached locals above. Call whenever stacking-related settings change.
function RBP.RefreshStackingConfig()
	local preset = RBP.dbp.stackingPreset ~= "Custom" and RBP.StackingPresets[RBP.dbp.stackingPreset]
	if not preset then
		preset = {
			springFrequencyRaise = RBP.dbp.stacking_springFrequencyRaise,
			springFrequencyLower = RBP.dbp.stacking_springFrequencyLower,
			launchDamping = RBP.dbp.stacking_launchDamping,
			settleThreshold = RBP.dbp.stacking_settleThreshold,
			maxPlates = RBP.dbp.stacking_maxPlates,
		}
	end
	omegaRaise = preset.springFrequencyRaise
	omegaLower = preset.springFrequencyLower
	launchDamping = preset.launchDamping
	launchDampingComplement = 1 - launchDamping
	settleThreshold = preset.settleThreshold
	maxPlates = preset.maxPlates

	xspace = RBP.dbp.xspace * (RBP.dbp.globalScale or 1)
	yspace = RBP.dbp.yspace * (RBP.dbp.globalScale or 1)
	originpos = RBP.dbp.originpos
end

------------------------- Layout pass (throttled, dirty-gated, O(n^2)) -------------------------
local sortedPlates = {} -- reused array, avoids per-pass allocation
local layoutLastRun = 0

local function CollectAndSort()
	local count = 0
	for Plate, data in pairs(StackablePlates) do
		local x, y = select(4, Plate:GetPoint(1))
		x, y = x or 0, y or 0
		data.velocity = data.velocity or 0
		data.position = data.position or 0
		data.targetOffset = data.targetOffset or 0
		data.xpos, data.ypos = x, y
		count = count + 1
		sortedPlates[count] = Plate
	end
	for i = #sortedPlates, count + 1, -1 do
		sortedPlates[i] = nil
	end
	sort(sortedPlates, function(a, b) return StackablePlates[a].ypos > StackablePlates[b].ypos end)
	return count
end

local function IsLayoutDirty(count)
	local prevCount = RBP.stackingPrevPlateCount or 0
	if count ~= prevCount then
		RBP.stackingPrevPlateCount = count
		return true
	end
	for i = 1, count do
		local data = StackablePlates[sortedPlates[i]]
		if not data.prevX or math_abs(data.xpos - data.prevX) > POSITION_DIRTY_THRESHOLD or math_abs(data.ypos - data.prevY) > POSITION_DIRTY_THRESHOLD then
			return true
		end
	end
	return false
end

--- Computes each stackable plate's target vertical offset by packing plates that
-- overlap in the same horizontal column, processed nearest-to-camera-first so
-- already-placed plates act as obstacles for the ones behind them.
local function DoLayoutUpdate()
	local count = CollectAndSort()
	if count == 0 then return end
	if not IsLayoutDirty(count) then
		-- prevX/prevY deliberately left stale here: next pass compares fresh
		-- position against this same reference, so slow cumulative drift still
		-- eventually crosses POSITION_DIRTY_THRESHOLD and triggers a recompute.
		return
	end

	local processCount = math_min(count, maxPlates)
	for i = 1, processCount do
		local Plate = sortedPlates[i]
		local data = StackablePlates[Plate]
		local _, height = Plate:GetSize()
		local target = 0
		for j = 1, i - 1 do
			local otherPlate = sortedPlates[j]
			local otherData = StackablePlates[otherPlate]
			if math_abs(data.xpos - otherData.xpos) < xspace then
				local requiredGap = otherData.ypos + otherData.targetOffset - data.ypos + yspace
				if requiredGap > target then
					target = requiredGap
				end
			end
		end
		data.targetOffset = target
		data.prevX, data.prevY = data.xpos, data.ypos
	end
	-- Plates beyond the cap never stack; just settle back to their native position.
	for i = processCount + 1, count do
		local data = StackablePlates[sortedPlates[i]]
		data.targetOffset = 0
		data.prevX, data.prevY = data.xpos, data.ypos
	end
end

------------------------- Animation pass (every frame, O(n), implicit spring) -------------------------
local function SpringStep(position, velocity, target, dt)
	local delta = target - position
	if math_abs(delta) < settleThreshold and math_abs(velocity) < SETTLE_VELOCITY then
		return target, 0, true
	end

	local raising = delta > 0 or velocity > SETTLE_VELOCITY
	local omega = raising and omegaRaise or omegaLower

	local dist = math_abs(delta)
	local omegaScale = launchDamping + launchDampingComplement * (1 - (dist < 20 and dist * INV_DIST_THRESHOLD or 1))
	omega = omega * omegaScale
	local oo = omega * omega

	local f = 1 + 2 * omega * dt
	local dt_oo = dt * oo
	local dt2_oo = dt * dt_oo
	local invDet = 1 / (f + dt2_oo)

	local newPosition = (f * position + dt * velocity + dt2_oo * target) * invDet
	local newVelocity = (velocity + dt_oo * (target - position)) * invDet
	return newPosition, newVelocity, false
end

local function ApplyPlateOffset(Plate, data)
	local width, height = Plate:GetSize()
	Plate:SetClampedToScreen(true)

	local bottomInset
	local isClampedTop = (Plate.isTarget and RBP.dbp.clampTarget) or (Plate.hasBossIcon and RBP.dbp.clampBoss and RBP.inPvEInstance)
	if isClampedTop then
		bottomInset = -data.ypos - data.position - originpos + height
		if data.lastLeft ~= 0.5 * width or data.lastTop ~= RBP.dbp.upperborder or data.lastBottom ~= bottomInset or data.lastClampMode ~= "top" then
			Plate:SetClampRectInsets(0.5 * width, -0.5 * width, RBP.dbp.upperborder, bottomInset)
			data.lastLeft, data.lastTop, data.lastBottom, data.lastClampMode = 0.5 * width, RBP.dbp.upperborder, bottomInset, "top"
		end
	else
		bottomInset = -data.ypos - data.position - originpos + height
		if data.lastLeft ~= 0.5 * width or data.lastTop ~= -height or data.lastBottom ~= bottomInset or data.lastClampMode ~= "free" then
			Plate:SetClampRectInsets(0.5 * width, -0.5 * width, -height, bottomInset)
			data.lastLeft, data.lastTop, data.lastBottom, data.lastClampMode = 0.5 * width, -height, bottomInset, "free"
		end
	end
end

local function DoAnimationUpdate(dt)
	if dt > MAX_DT then dt = MAX_DT end
	for Plate, data in pairs(StackablePlates) do
		-- A plate can be registered (Functions.lua sets xpos/ypos/position only) and
		-- picked up here before the throttled layout pass has ever run for it, which is
		-- the only other place velocity/targetOffset get initialized -- guard here too
		-- so this doesn't race and compare against nil.
		data.velocity = data.velocity or 0
		data.targetOffset = data.targetOffset or 0
		if RBP.dbp.FreezeMouseover and Plate.VirtualPlate.healthBarHighlight:IsShown() then
			-- Frozen: pin using live center position, matching the classic implementation.
			local x, y = Plate:GetCenter()
			local width, height = Plate:GetSize()
			data.position = y - data.ypos - originpos + height / 2
			data.velocity = 0
			Plate:SetClampedToScreen(true)
			Plate:SetClampRectInsets(-2 * RBP.WorldFrameWidth, RBP.WorldFrameWidth - x - width / 2, 768 - y - height / 2, -2 * 768)
			data.lastClampMode = nil -- force a fresh apply once unfrozen
		else
			if data.position < 0.5 and data.targetOffset < 0.5 and math_abs(data.velocity or 0) < SETTLE_VELOCITY then
				-- Already at rest at the unstacked baseline. ApplyPlateOffset has its own
				-- last-value guard, so this is a cheap no-op once the clamp is already set.
				ApplyPlateOffset(Plate, data)
			else
				local newPosition, newVelocity, settled = SpringStep(data.position, data.velocity or 0, data.targetOffset, dt)
				data.position, data.velocity, data.isSettled = newPosition, newVelocity, settled
				ApplyPlateOffset(Plate, data)
			end
		end
	end
end

------------------------- Driver -------------------------
local StackingDriver = CreateFrame("Frame")

local function OnStackingUpdate(self, elapsed)
	if RBP.dbp.stackingInInstance and not RBP.inInstance then return end
	local now = GetTime()
	if now - layoutLastRun >= LAYOUT_INTERVAL then
		layoutLastRun = now
		DoLayoutUpdate()
	end
	DoAnimationUpdate(elapsed)
end

--- Enables/disables the stacking driver. No OnUpdate is registered at all while disabled,
-- matching TurboPlates' "hidden frame's OnUpdate doesn't fire" pattern for zero idle cost.
function RBP.SetStackingEnabled(enabled)
	if enabled then
		layoutLastRun = 0
		RBP.stackingPrevPlateCount = nil
		StackingDriver:SetScript("OnUpdate", OnStackingUpdate)
	else
		StackingDriver:SetScript("OnUpdate", nil)
	end
end
