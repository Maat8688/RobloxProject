--!strict
-- Shift-lock style camera: the character always faces where the camera faces,
-- so movement becomes strafe-relative instead of turn-to-move.
--
-- Combat needs this. Parry timing is read off the enemy's telegraph, and with
-- free-look the player has to choose between watching the wind-up and steering
-- — which turns a timing test into a camera-wrangling test. Locked facing keeps
-- the enemy on screen while circling.
--
-- Toggled rather than held: a hold would fight the parry and attack binds
-- during the exact moments it matters most.
--
-- Rotation goes through an AlignOrientation constraint rather than writing
-- HumanoidRootPart.CFrame each frame. Overwriting the CFrame of a part the
-- physics solver also owns makes the two fight, and the correction is visible
-- as per-frame jitter. Setting a constraint's goal orientation instead lets the
-- solver do the rotating, so there is nothing to fight.

local ContextActionService = game:GetService("ContextActionService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local CameraLock = {}

local TOGGLE_ACTION = "ToggleCameraLock"
local RENDER_STEP_NAME = "CameraLockFacing"

-- Nudges the character off-centre so the crosshair isn't buried in their head.
-- Matches the direction Roblox's built-in shift lock offsets to.
local SHOULDER_OFFSET = Vector3.new(1.75, 0, 0)

local player = Players.LocalPlayer
local locked = false

local attachment: Attachment? = nil
local alignOrientation: AlignOrientation? = nil

local function getHumanoid(): Humanoid?
	local character = player.Character
	if not character then
		return nil
	end
	return character:FindFirstChildOfClass("Humanoid")
end

local function getRoot(): BasePart?
	local character = player.Character
	if not character then
		return nil
	end
	return character:FindFirstChild("HumanoidRootPart") :: BasePart?
end

local function destroyConstraint()
	if alignOrientation then
		alignOrientation:Destroy()
		alignOrientation = nil
	end
	if attachment then
		attachment:Destroy()
		attachment = nil
	end
end

-- Rebuilt rather than reparented on respawn, since the old character's root is
-- gone and the constraint dies with it.
local function ensureConstraint(): AlignOrientation?
	local root = getRoot()
	if not root then
		return nil
	end

	if alignOrientation and alignOrientation.Parent == root then
		return alignOrientation
	end

	destroyConstraint()

	local newAttachment = Instance.new("Attachment")
	newAttachment.Name = "CameraLockAttachment"
	newAttachment.Parent = root

	local newAlign = Instance.new("AlignOrientation")
	newAlign.Name = "CameraLockOrientation"
	-- OneAttachment aligns the attachment to a world-space goal CFrame, which
	-- is what we want — there is no second part to align against.
	newAlign.Mode = Enum.OrientationAlignmentMode.OneAttachment
	newAlign.Attachment0 = newAttachment
	-- Rigid rather than springy: "always looks in the same direction" means the
	-- character should not lag behind the camera on a spring.
	newAlign.RigidityEnabled = true
	newAlign.Parent = root

	attachment = newAttachment
	alignOrientation = newAlign

	return newAlign
end

-- Applied on every toggle and again on respawn, since a new character comes
-- back with default AutoRotate and no camera offset.
local function applyToCharacter()
	local humanoid = getHumanoid()
	if not humanoid then
		return
	end

	-- AutoRotate turns the character toward its movement direction, which is
	-- exactly what the constraint is replacing. Leaving it on would be a third
	-- system competing for the same rotation.
	humanoid.AutoRotate = not locked
	humanoid.CameraOffset = if locked then SHOULDER_OFFSET else Vector3.zero

	if locked then
		ensureConstraint()
	else
		destroyConstraint()
	end
end

local function onRenderStep()
	if not locked then
		return
	end

	-- Other systems (and Roblox itself, on respawn or menu close) can reset
	-- this, so it's re-asserted rather than set once.
	UserInputService.MouseBehavior = Enum.MouseBehavior.LockCenter

	local humanoid = getHumanoid()
	if not humanoid or humanoid.Health <= 0 then
		return
	end

	local align = ensureConstraint()
	if not align then
		return
	end

	local look = Workspace.CurrentCamera.CFrame.LookVector
	-- Flattened to the XZ plane: looking up or down must not tip the character.
	local flat = Vector3.new(look.X, 0, look.Z)
	if flat.Magnitude < 1e-4 then
		return
	end

	-- Only the orientation of this CFrame is used, so the position stays at
	-- the origin. This is a goal for the solver, not a teleport.
	align.CFrame = CFrame.lookAt(Vector3.zero, flat.Unit)
end

function CameraLock.setLocked(value: boolean)
	locked = value
	applyToCharacter()

	if locked then
		UserInputService.MouseBehavior = Enum.MouseBehavior.LockCenter
		-- Runs after the camera has moved this frame, so the goal reflects
		-- where the camera actually ended up rather than lagging a frame.
		RunService:BindToRenderStep(RENDER_STEP_NAME, Enum.RenderPriority.Character.Value, onRenderStep)
	else
		UserInputService.MouseBehavior = Enum.MouseBehavior.Default
		RunService:UnbindFromRenderStep(RENDER_STEP_NAME)
	end
end

function CameraLock.isLocked(): boolean
	return locked
end

function CameraLock.start()
	ContextActionService:BindAction(TOGGLE_ACTION, function(_, inputState)
		if inputState == Enum.UserInputState.Begin then
			CameraLock.setLocked(not locked)
		end
		return Enum.ContextActionResult.Sink
	end, false, Enum.KeyCode.LeftShift)

	player.CharacterAdded:Connect(function()
		-- The old constraint died with the old character.
		destroyConstraint()
		-- Wait for the Humanoid to exist before touching AutoRotate.
		task.defer(applyToCharacter)
	end)

	-- On by default: the combat slice is the reason this exists.
	CameraLock.setLocked(true)
end

return CameraLock
