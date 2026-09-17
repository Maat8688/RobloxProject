--!strict
-- Client bootstrap.

local CameraLock = require(script.CameraLock)
local CombatClient = require(script.CombatClient)
local DebugHUD = require(script.DebugHUD)
local EnemyAnimation = require(script.EnemyAnimation)
local GameUI = require(script.GameUI)
local PlayerAnimation = require(script.PlayerAnimation)
local TelegraphVFX = require(script.TelegraphVFX)
local WorldFeedback = require(script.WorldFeedback)

CameraLock.start()
PlayerAnimation.start()
CombatClient.start()
EnemyAnimation.start()
TelegraphVFX.start()
WorldFeedback.start()
GameUI.start()
DebugHUD.start()
