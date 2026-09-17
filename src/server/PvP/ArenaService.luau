--!strict
-- 1v1 PvP arena (build-order step 9). One shared arena and one active duel at a
-- time — a third or fourth queued player waits for the current duel to end.
-- Multiple concurrent arenas are a reasonable later enhancement, not a gap:
-- PvP is a secondary mode reusing PvE's combat system, not something that
-- needs day-one matchmaking scale (DESIGN.md).
--
-- Owns the arena room, the queue, and who is dueling whom. PvPCombatServer
-- owns resolving swings and parries within whatever duel this module says is
-- running — the same split as DungeonGenerator (places enemies) vs.
-- CombatServer (resolves combat against them).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Remotes = require(ReplicatedStorage.Shared.Remotes)

local RoomTemplates = require(script.Parent.Parent.Dungeon.RoomTemplates)
local Duelist = require(script.Parent.Duelist)

-- Well clear of the dungeon, which only ever extends toward +Z from the start
-- room, so no run of combat rooms can ever reach it.
local ARENA_OFFSET = Vector3.new(0, 0, -200)
local QUEUE_STAND_OFFSET = Vector3.new(10, 2, -8)
local RETURN_OFFSET = Vector3.new(0, 3, 0)
local SPAWN_INSET = 15
local RETURN_DELAY = 1

local ArenaService = {}

type Duel = {
	players: { Player },
	duelists: { [Player]: Duelist.Duelist },
}

local queue: { Player } = {}
local activeDuel: Duel? = nil
local originReturnCFrame = CFrame.new()
local arenaBaseCFrame = CFrame.new()

local function publishStatus(player: Player, status: string, opponentName: string?, message: string?)
	if player.Parent then
		Remotes.get("PvPStatusChanged"):FireClient(player, {
			status = status,
			opponentName = opponentName,
			message = message,
		})
	end
end

local function teleportTo(player: Player, cframe: CFrame)
	local character = player.Character
	if character and character:FindFirstChild("HumanoidRootPart") then
		character:PivotTo(cframe)
	end
end

function ArenaService.publishHealth()
	local duel = activeDuel
	if not duel then
		return
	end

	local a, b = duel.players[1], duel.players[2]
	local healthA, healthB = duel.duelists[a].health, duel.duelists[b].health

	if a.Parent then
		Remotes.get("PvPHealthChanged"):FireClient(a, { yours = healthA, opponent = healthB })
	end
	if b.Parent then
		Remotes.get("PvPHealthChanged"):FireClient(b, { yours = healthB, opponent = healthA })
	end
end

local function tryStartNextDuel()
	while activeDuel == nil and #queue >= 2 do
		local a = table.remove(queue, 1) :: Player
		local b = table.remove(queue, 1) :: Player

		-- Anyone who left while queued is dropped; whoever's still here keeps
		-- their place at the front.
		if not (a.Parent and b.Parent) then
			if a.Parent then
				table.insert(queue, 1, a)
			elseif b.Parent then
				table.insert(queue, 1, b)
			end
			continue
		end

		activeDuel = {
			players = { a, b },
			duelists = { [a] = Duelist.new(a), [b] = Duelist.new(b) },
		}

		-- A CFrame's default facing is -Z. The player at -Z is turned around so
		-- the two start facing each other rather than one facing the wall.
		teleportTo(a, arenaBaseCFrame * CFrame.new(0, 3, -SPAWN_INSET) * CFrame.Angles(0, math.pi, 0))
		teleportTo(b, arenaBaseCFrame * CFrame.new(0, 3, SPAWN_INSET))

		publishStatus(a, "dueling", b.Name)
		publishStatus(b, "dueling", a.Name)
		ArenaService.publishHealth()
	end
end

local function endDuel(loser: Player, message: string?)
	local duel = activeDuel
	if not duel or not duel.duelists[loser] then
		return
	end

	local a, b = duel.players[1], duel.players[2]
	local winner = if loser == a then b else a

	publishStatus(winner, "idle", nil, message or `You defeated {loser.Name}!`)
	publishStatus(loser, "idle", nil, message or `{winner.Name} defeated you.`)

	activeDuel = nil

	task.delay(RETURN_DELAY, function()
		teleportTo(winner, originReturnCFrame)
		teleportTo(loser, originReturnCFrame)
		tryStartNextDuel()
	end)
end

function ArenaService.start(originCFrame: CFrame)
	originReturnCFrame = originCFrame * CFrame.new(RETURN_OFFSET)
	arenaBaseCFrame = originCFrame * CFrame.new(ARENA_OFFSET)

	local arena = RoomTemplates.build("Empty", arenaBaseCFrame, false, false)
	arena.model.Name = "Arena"
	arena.model.Parent = Workspace

	local stand = Instance.new("Part")
	stand.Name = "DuelQueue"
	stand.Anchored = true
	stand.CanCollide = true
	stand.Size = Vector3.new(2, 4, 2)
	stand.Color = Color3.fromRGB(13, 105, 172)
	stand.CFrame = originCFrame * CFrame.new(QUEUE_STAND_OFFSET)
	stand.Parent = Workspace

	local prompt = Instance.new("ProximityPrompt")
	prompt.ObjectText = "Duel Arena"
	prompt.ActionText = "Queue"
	prompt.HoldDuration = 0
	prompt.MaxActivationDistance = 8
	prompt.Parent = stand

	-- Triggering again while queued leaves the queue.
	prompt.Triggered:Connect(function(player)
		local duel = activeDuel
		if duel and duel.duelists[player] then
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

		local duel = activeDuel
		if duel and duel.duelists[player] then
			endDuel(player, `{player.Name} left the duel.`)
		end
	end)
end

-- This player's own Duelist, if they're in the active duel.
function ArenaService.getDuelist(player: Player): Duelist.Duelist?
	local duel = activeDuel
	if not duel then
		return nil
	end

	return duel.duelists[player]
end

-- The opposing Duelist and Player, or nil if `player` isn't dueling.
function ArenaService.getOpponent(player: Player): (Duelist.Duelist?, Player?)
	local duel = activeDuel
	if not duel or not duel.duelists[player] then
		return nil, nil
	end

	local a, b = duel.players[1], duel.players[2]
	local opponent = if player == a then b else a
	return duel.duelists[opponent], opponent
end

-- Called by PvPCombatServer once a duelist's health reaches zero.
function ArenaService.endDuel(loser: Player)
	endDuel(loser)
end

return ArenaService
