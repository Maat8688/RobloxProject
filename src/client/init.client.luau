--!strict
-- Vertical slice client bootstrap.

local CombatClient = require(script.CombatClient)
local DebugHUD = require(script.DebugHUD)
local TelegraphVFX = require(script.TelegraphVFX)

CombatClient.start()
TelegraphVFX.start()
DebugHUD.start()
