
--[[--------------------------------------------------------------------------------
-- ModelSceneMain是主场景。刚打开游戏，以及退出战局后所看到的就是这个场景。
--
-- 主要职责和使用场景举例：
--   同上
--
-- 其他：
--  - 目前本类功能很少。预定需要增加的功能包括（在本类中直接实现，或通过添加新的类来实现）：
--	- 创建新战局
--	- 加入已有战局
--	- 配置技能
--	- 显示玩家形象、id、积分、排名、战绩
--]]--------------------------------------------------------------------------------

local ModelSceneMain = class("ModelSceneMain")

local ActionCodeFunctions		= requireFW("src.app.utilities.ActionCodeFunctions")
local ActionExecutorForSceneMain = requireFW("src.app.utilities.actionExecutors.ActionExecutorForSceneMain")
local AudioManager			   = requireFW("src.app.utilities.AudioManager")
local GameConstantFunctions	  = requireFW("src.app.utilities.GameConstantFunctions")
local LocalizationFunctions	  = requireFW("src.app.utilities.LocalizationFunctions")
local SerializationFunctions	 = requireFW("src.app.utilities.SerializationFunctions")
local WebSocketManager		   = requireFW("src.app.utilities.WebSocketManager")
local Actor					  = requireFW("src.global.actors.Actor")
local ActorManager			   = requireFW("src.global.actors.ActorManager")
local EventDispatcher			= requireFW("src.global.events.EventDispatcher")

local getLocalizedText = LocalizationFunctions.getLocalizedText
local string		   = string

--------------------------------------------------------------------------------
-- The private callback function on web socket events.
--------------------------------------------------------------------------------
local function onWebSocketMessage(self, param)
	local actionCode = param.action.actionCode
	print(string.format("ModelSceneMain-onWebSocketMessage() code: %d  name: %s  length: %d",
		actionCode,
		ActionCodeFunctions.getActionName(actionCode),
		string.len(param.message))
	)
	print(SerializationFunctions.toString(param.action))
	ActionExecutorForSceneMain.execute(param.action,self)
end

--------------------------------------------------------------------------------
-- The composition elements.
--------------------------------------------------------------------------------
local function initActorConfirmBox(self, confirmText)
	local actor = Actor.createWithModelAndViewName("common.ModelConfirmBox", nil, "common.ViewConfirmBox")
	if (not confirmText) then
		actor:getModel():setEnabled(false)
	else
		actor:getModel():setConfirmText(confirmText)
	end

	self.m_ActorConfirmBox = actor
end

local function initActorMessageIndicator(self)
	local actor = Actor.createWithModelAndViewName("common.ModelMessageIndicator", nil, "common.ViewMessageIndicator")

	self.m_ActorMessageIndicator = actor
end

local function initActorMainMenu(self)
	local actor = Actor.createWithModelAndViewName("sceneMain.ModelMainMenu", nil, "sceneMain.ViewMainMenu")
	self.m_ActorMainMenu = actor
end

--------------------------------------------------------------------------------
-- The constructor and initializers.
--------------------------------------------------------------------------------
function ModelSceneMain:ctor(param)
	print('ModelSceneMain构造函数')
	param = param or {}

	self.m_ScriptEventDispatcher = EventDispatcher:create()
	initActorConfirmBox(	  self, param.confirmText)
	initActorMessageIndicator(self)
	initActorMainMenu(		self)

	if (self.m_View) then
		self:initView()
	end

	return self
end

function ModelSceneMain:initView()
	self.m_View:setViewConfirmBox(	  self.m_ActorConfirmBox:getView())
		:setViewMainMenu(		self.m_ActorMainMenu:getView())
		:setViewMessageIndicator(self.m_ActorMessageIndicator:getView())
		:setGameVersion(GameConstantFunctions.getGameVersion())
	return self
end

--------------------------------------------------------------------------------
-- The callback function on start running/script/web socket events.
--------------------------------------------------------------------------------
function ModelSceneMain:onStartRunning()
	self:getModelMainMenu():onStartRunning(self)
	AudioManager.playMainMusic()
	return self
end

function ModelSceneMain:onWebSocketEvent(eventName, param)
	if (eventName == "open")then
		self:getModelMessageIndicator():showMessage(getLocalizedText(30, "ConnectionEstablished"))
	elseif (eventName == "message") then
		onWebSocketMessage(self, param)
	elseif (eventName == "close")then
		self:getModelMessageIndicator():showMessage(getLocalizedText(31))
	elseif (eventName == "error") then
		self:getModelMessageIndicator():showMessage(getLocalizedText(32, param.error))
	end
	return self
end

--------------------------------------------------------------------------------
-- The public functions.
--------------------------------------------------------------------------------
function ModelSceneMain:getModelConfirmBox()
	return self.m_ActorConfirmBox:getModel()
end

function ModelSceneMain:getModelMainMenu()
	return self.m_ActorMainMenu:getModel()
end

function ModelSceneMain:getModelMessageIndicator()
	return self.m_ActorMessageIndicator:getModel()
end

function ModelSceneMain:getScriptEventDispatcher()
	return self.m_ScriptEventDispatcher
end

return ModelSceneMain
