--!strict
-- Client bootstrap.

local CameraLock = require(script.CameraLock)
local CombatClient = require(script.CombatClient)
local DebugHUD = require(script.DebugHUD)
local GameUI = require(script.GameUI)
local TelegraphVFX = require(script.TelegraphVFX)

CameraLock.start()
CombatClient.start()
TelegraphVFX.start()
GameUI.start()
DebugHUD.start()
