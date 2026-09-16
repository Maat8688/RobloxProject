--!strict
-- Vertical slice client bootstrap.

local CameraLock = require(script.CameraLock)
local CombatClient = require(script.CombatClient)
local DebugHUD = require(script.DebugHUD)
local TelegraphVFX = require(script.TelegraphVFX)

CameraLock.start()
CombatClient.start()
TelegraphVFX.start()
DebugHUD.start()
