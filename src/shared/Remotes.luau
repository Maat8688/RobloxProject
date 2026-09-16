--!strict
-- Every RemoteEvent/RemoteFunction in the game is created here and nowhere
-- else (ARCHITECTURE.md). Anything added must also get a row in that file's
-- remote registry table.
--
-- The server creates the instances; the client waits for them. Both sides call
-- Remotes.get(name) and neither needs to know which case it is in.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Remotes = {}

local FOLDER_NAME = "Remotes"

local REMOTE_EVENTS = {
	-- Client -> Server
	"ParryAttempt",
	"AttackRequest",
	"EquipWeapon",
	-- Server -> Client
	"EnemyTelegraphStart",
	"PlayerHit",
	"ParryResult",
	"EnemyStaggered",
	"AttackResult",
	"WeaponEquipped",
	"EnemyHealthChanged",
}

local folder: Folder? = nil

local function buildOnServer(): Folder
	local existing = ReplicatedStorage:FindFirstChild(FOLDER_NAME)
	if existing then
		return existing :: Folder
	end

	local created = Instance.new("Folder")
	created.Name = FOLDER_NAME

	for _, remoteName in REMOTE_EVENTS do
		local remote = Instance.new("RemoteEvent")
		remote.Name = remoteName
		remote.Parent = created
	end

	created.Parent = ReplicatedStorage
	return created
end

local function resolveFolder(): Folder
	if folder then
		return folder
	end

	if RunService:IsServer() then
		folder = buildOnServer()
	else
		folder = ReplicatedStorage:WaitForChild(FOLDER_NAME) :: Folder
	end

	return folder :: Folder
end

-- Call once from the server bootstrap, before anything tries to connect, so
-- the folder exists by the time clients start waiting on it.
function Remotes.init()
	assert(RunService:IsServer(), "Remotes.init must be called from the server")
	resolveFolder()
end

function Remotes.get(name: string): RemoteEvent
	local remote = resolveFolder():WaitForChild(name, 10)
	assert(remote, `Remote "{name}" was never created — add it to REMOTE_EVENTS`)
	return remote :: RemoteEvent
end

return Remotes
