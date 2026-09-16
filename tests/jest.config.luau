--!strict
-- Jest project config. Lives outside src/ so no test scaffolding is published
-- into the game place — default.project.json never mounts this folder.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

return {
	testMatch = { "**/*.spec" },
	roots = { ReplicatedStorage.Shared },
}
