
local ModelWarFieldForReplay = requireFW("src.global.functions.class")("ModelWarFieldForReplay")

local SingletonGetters = requireFW("src.app.utilities.SingletonGetters")
local Actor            = requireFW("src.global.actors.Actor")

local IS_SERVER               = requireFW("src.app.utilities.GameConstantFunctions").isServer()

--------------------------------------------------------------------------------
-- The private callback functions on script events.
--------------------------------------------------------------------------------
local function onEvtDragField(self, event)
    self.m_View:setPositionOnDrag(event.previousPosition, event.currentPosition)
end

local function onEvtZoomFieldWithScroll(self, event)
    local scrollEvent = event.scrollEvent
    self.m_View:setZoomWithScroll(cc.Director:getInstance():convertToGL(scrollEvent:getLocation()), scrollEvent:getScrollY())
end

local function onEvtZoomFieldWithTouches(self, event)
    self.m_View:setZoomWithTouches(event.touches)
end

--------------------------------------------------------------------------------
-- The composition elements.
--------------------------------------------------------------------------------
local function initActorActionPlanner(self)
    if (not self.m_ActorActionPlanner) then
        self.m_ActorActionPlanner = Actor.createWithModelAndViewName("sceneWar.ModelActionPlanner", nil, "sceneWar.ViewActionPlanner")
    end
end

local function initActorFogMap(self, fogMapData, isTotalReplay)
    if (not self.m_ActorFogMap) then
        local modelFogMap  = Actor.createModel("sceneWar.ModelFogMap", fogMapData, self.m_WarFieldFileName, isTotalReplay)
        self.m_ActorFogMap = ((IS_SERVER) or (not isTotalReplay))                                        and
            (Actor.createWithModelAndViewInstance(modelFogMap))                                          or
            (Actor.createWithModelAndViewInstance(modelFogMap, Actor.createView("sceneWar.ViewFogMap")))
    else
        self.m_ActorFogMap:getModel():ctor(fogMapData, self.m_WarFieldFileName, isTotalReplay)
    end
end

local function initActorGridEffect(self)
    if (not self.m_ActorGridEffect) then
        self.m_ActorGridEffect = Actor.createWithModelAndViewName("common.ModelGridEffect", nil, "common.ViewGridEffect")
    end
end

local function initActorTileMap(self, tileMapData)
    if (not self.m_ActorTileMap) then
        local modelTileMap  = Actor.createModel("sceneWar.ModelTileMap", tileMapData, self.m_WarFieldFileName)
        self.m_ActorTileMap = (IS_SERVER)                                                                  and
            (Actor.createWithModelAndViewInstance(modelTileMap))                                           or
            (Actor.createWithModelAndViewInstance(modelTileMap, Actor.createView("sceneWar.ViewTileMap")))
    else
        self.m_ActorTileMap:getModel():ctor(tileMapData, self.m_WarFieldFileName)
    end
end

local function initActorUnitMap(self, unitMapData)
    if (not self.m_ActorUnitMap) then
        local modelUnitMap  = Actor.createModel("sceneWar.ModelUnitMap", unitMapData, self.m_WarFieldFileName)
        self.m_ActorUnitMap = (IS_SERVER)                                                                  and
            (Actor.createWithModelAndViewInstance(modelUnitMap))                                           or
            (Actor.createWithModelAndViewInstance(modelUnitMap, Actor.createView("sceneWar.ViewUnitMap")))
    else
        self.m_ActorUnitMap:getModel():ctor(unitMapData, self.m_WarFieldFileName)
    end
end

local function initActorMapCursor(self, param)
    if (not self.m_ActorMapCursor) then
        self.m_ActorMapCursor = Actor.createWithModelAndViewName("sceneWar.ModelMapCursor", param, "sceneWar.ViewMapCursor")
    end
end

--------------------------------------------------------------------------------
-- The constructor and initializers.
--------------------------------------------------------------------------------
function ModelWarFieldForReplay:ctor(warFieldData)
    self.m_WarFieldFileName = warFieldData.warFieldFileName

    initActorActionPlanner(self)
    initActorFogMap(       self, warFieldData.fogMap,  isTotalReplay)
    initActorGridEffect(   self)
    initActorTileMap(      self, warFieldData.tileMap)
    initActorUnitMap(      self, warFieldData.unitMap)

    if (not IS_SERVER) then
        initActorMapCursor(    self, {mapSize = self:getModelTileMap():getMapSize()})
    end

    return self
end

function ModelWarFieldForReplay:initView()
    assert(self.m_View, "ModelWarFieldForReplay:initView() no view is attached to the owner actor of the model.")
    self.m_View:setViewTileMap(self.m_ActorTileMap      :getView())
        :setViewUnitMap(       self.m_ActorUnitMap      :getView())
        :setViewActionPlanner( self.m_ActorActionPlanner:getView())
        :setViewMapCursor(     self.m_ActorMapCursor    :getView())
        :setViewGridEffect(    self.m_ActorGridEffect   :getView())

        :setContentSizeWithMapSize(self:getModelTileMap():getMapSize())

    local viewFogMap = self.m_ActorFogMap:getView()
    if (viewFogMap) then
        self.m_View:setViewFogMap(viewFogMap)
    end

    return self
end

--------------------------------------------------------------------------------
-- The callback functions on start running/script events.
--------------------------------------------------------------------------------
function ModelWarFieldForReplay:onStartRunning(modelWarReplay)
    self:getModelTileMap()      :onStartRunning(modelWarReplay)
    self:getModelUnitMap()      :onStartRunning(modelWarReplay)
    self:getModelFogMap()       :onStartRunning(modelWarReplay)
    self:getModelActionPlanner():onStartRunning(modelWarReplay)

    if (not IS_SERVER) then
        self.m_ActorGridEffect   :getModel():onStartRunning(modelWarReplay)
        self.m_ActorMapCursor    :getModel():onStartRunning(modelWarReplay)

        self:getModelTileMap():updateOnModelFogMapStartedRunning()
    end

    SingletonGetters.getScriptEventDispatcher(modelWarReplay)
        :addEventListener("EvtDragField",            self)
        :addEventListener("EvtZoomFieldWithScroll",  self)
        :addEventListener("EvtZoomFieldWithTouches", self)

    return self
end

function ModelWarFieldForReplay:onEvent(event)
    local eventName = event.name
    if     (eventName == "EvtDragField")            then onEvtDragField(           self, event)
    elseif (eventName == "EvtZoomFieldWithScroll")  then onEvtZoomFieldWithScroll( self, event)
    elseif (eventName == "EvtZoomFieldWithTouches") then onEvtZoomFieldWithTouches(self, event)
    end

    return self
end

--------------------------------------------------------------------------------
-- The public functions.
--------------------------------------------------------------------------------
function ModelWarFieldForReplay:getWarFieldFileName()
    return self.m_WarFieldFileName
end

function ModelWarFieldForReplay:getModelActionPlanner()
    return self.m_ActorActionPlanner:getModel()
end

function ModelWarFieldForReplay:getModelFogMap()
    return self.m_ActorFogMap:getModel()
end

function ModelWarFieldForReplay:getModelUnitMap()
    return self.m_ActorUnitMap:getModel()
end

function ModelWarFieldForReplay:getModelTileMap()
    return self.m_ActorTileMap:getModel()
end

function ModelWarFieldForReplay:getModelMapCursor()
    return self.m_ActorMapCursor:getModel()
end

function ModelWarFieldForReplay:getModelGridEffect()
    return self.m_ActorGridEffect:getModel()
end

return ModelWarFieldForReplay
