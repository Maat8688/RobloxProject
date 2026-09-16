-- 1v1 PvP arena (build order step 9). A single shared arena and a single
-- active duel at a time — a third/fourth player queuing just waits for the
-- current duel to end. Scaling to multiple concurrent arenas is a reasonable
-- later enhancement, not a gap: DESIGN.md treats PvP as reusing PvE's combat
-- system as a secondary mode, not something that needs day-one matchmaking
-- scale.
--
-- Owns: the arena room, the queue, and who is currently dueling whom.
-- PvPCombatServer owns the actual attack/parry resolution against whatever
-- this module says the current duel is — same split as
-- DungeonGenerator (spawns/owns enemies) vs. CombatServer (resolves combat
-- against them).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Remotes = require(Shared:WaitForChild("Remotes"))

local RoomTemplates = require(script.Parent.Parent.Dungeon.RoomTemplates)
local Duelist = require(script.Parent.Duelist)

local pvpStatusRemote = Remotes.Get(Remotes.Names.PvPStatusChanged)
local pvpHealthRemote = Remotes.Get(Remotes.Names.PvPHealthChanged)

-- Well clear of the dungeon, which only ever extends toward +Z from the
-- start room (see DungeonGenerator) — an arena at -Z can never collide with
-- a long combat-room run.
local ARENA_OFFSET = Vector3.new(0, 0, -200)
local QUEUE_PROMPT_OFFSET = Vector3.new(10, 2, -8)
local RETURN_OFFSET = Vector3.new(0, 3, 0)
local SPAWN_INSET = 15

local ArenaService = {}

local queue = {}
local activeDuel = nil -- { players = { a, b }, [a] = Duelist, [b] = Duelist }
local originReturnCFrame

local function publishStatus(player, status, opponentName, resultMessage)
	if player.Parent then
		pvpStatusRemote:FireClient(player, status, opponentName, resultMessage)
	end
end

local function publishHealth()
	if activeDuel == nil then
		return
	end

	local a, b = activeDuel.players[1], activeDuel.players[2]
	local duelistA, duelistB = activeDuel[a], activeDuel[b]

	if a.Parent then
		pvpHealthRemote:FireClient(a, duelistA.health, duelistB.health)
	end
	if b.Parent then
		pvpHealthRemote:FireClient(b, duelistB.health, duelistA.health)
	end
end

local function teleportTo(player, cframe)
	local character = player.Character
	if character and character:FindFirstChild("HumanoidRootPart") then
		character:PivotTo(cframe)
	end
end

-- Forward-declared so startDuel/endDuel (defined below) can call each other
-- without an upvalue-ordering problem.
local tryStartNextDuel

local function endDuel(loser, reasonMessage)
	if activeDuel == nil or activeDuel[loser] == nil then
		return
	end

	local a, b = activeDuel.players[1], activeDuel.players[2]
	local winner = (loser == a) and b or a

	publishStatus(winner, "idle", nil, reasonMessage or ("You defeated " .. loser.Name .. "!"))
	publishStatus(loser, "idle", nil, reasonMessage or (winner.Name .. " defeated you."))

	activeDuel = nil

	task.delay(1, function()
		teleportTo(winner, originReturnCFrame)
		teleportTo(loser, originReturnCFrame)
		tryStartNextDuel()
	end)
end

local function startDuel(a, b, arenaBaseCFrame)
	local spawnA = arenaBaseCFrame * CFrame.new(0, 3, -SPAWN_INSET)
	local spawnB = arenaBaseCFrame * CFrame.new(0, 3, SPAWN_INSET)

	activeDuel = { players = { a, b }, [a] = Duelist.new(a), [b] = Duelist.new(b) }

	teleportTo(a, spawnA)
	teleportTo(b, spawnB)

	publishStatus(a, "dueling", b.Name)
	publishStatus(b, "dueling", a.Name)
	publishHealth()
end

function ArenaService.Start(originCFrame)
	originReturnCFrame = originCFrame * CFrame.new(RETURN_OFFSET)
	local arenaBaseCFrame = originCFrame * CFrame.new(ARENA_OFFSET)

	local arenaModel = RoomTemplates.Build("Empty", arenaBaseCFrame, false, false)
	arenaModel.Name = "Arena"
	arenaModel.Parent = Workspace

	tryStartNextDuel = function()
		while activeDuel == nil and #queue >= 2 do
			local a = table.remove(queue, 1)
			local b = table.remove(queue, 1)

			if a.Parent and b.Parent then
				startDuel(a, b, arenaBaseCFrame)
			elseif a.Parent then
				table.insert(queue, 1, a)
			elseif b.Parent then
				table.insert(queue, 1, b)
			end
		end
	end

	local queueStand = Instance.new("Part")
	queueStand.Name = "DuelQueue"
	queueStand.Anchored = true
	queueStand.CanCollide = true
	queueStand.Size = Vector3.new(2, 4, 2)
	queueStand.BrickColor = BrickColor.new("Bright blue")
	queueStand.CFrame = originCFrame * CFrame.new(QUEUE_PROMPT_OFFSET)
	queueStand.Parent = Workspace

	local prompt = Instance.new("ProximityPrompt")
	prompt.ObjectText = "Duel Arena"
	prompt.ActionText = "Queue"
	prompt.HoldDuration = 0
	prompt.MaxActivationDistance = 8
	prompt.Parent = queueStand

	prompt.Triggered:Connect(function(player)
		if activeDuel ~= nil and activeDuel[player] ~= nil then
			return
		end

		local queueIndex = table.find(queue, player)
		if queueIndex then
			table.remove(queue, queueIndex)
			publishStatus(player, "idle")
			return
		end

		table.insert(queue, player)
		publishStatus(player, "queued")
		tryStartNextDuel()
	end)

	Players.PlayerRemoving:Connect(function(player)
		local queueIndex = table.find(queue, player)
		if queueIndex then
			table.remove(queue, queueIndex)
		end

		if activeDuel ~= nil and activeDuel[player] ~= nil then
			endDuel(player, player.Name .. " left the duel.")
		end
	end)
end

-- Returns this player's own Duelist if they're currently in the active duel.
function ArenaService.GetDuelist(player)
	if activeDuel == nil then
		return nil
	end
	return activeDuel[player]
end

-- Returns the opposing Duelist and Player, or nil if `player` isn't dueling.
function ArenaService.GetOpponent(player)
	if activeDuel == nil or activeDuel[player] == nil then
		return nil, nil
	end

	local a, b = activeDuel.players[1], activeDuel.players[2]
	local opponentPlayer = (player == a) and b or a
	return activeDuel[opponentPlayer], opponentPlayer
end

function ArenaService.PublishHealth()
	publishHealth()
end

-- `loser` is the player whose Duelist health hit 0. PvPCombatServer calls
-- this once it detects that from Duelist:ApplyDamage.
function ArenaService.EndDuel(loser)
	endDuel(loser)
end

return ArenaService
