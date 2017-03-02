
local ModelSkillConfiguratorForOnline = class("ModelSkillConfiguratorForOnline")

local ActionCodeFunctions       = requireFW("src.app.utilities.ActionCodeFunctions")
local AuxiliaryFunctions        = requireFW("src.app.utilities.AuxiliaryFunctions")
local LocalizationFunctions     = requireFW("src.app.utilities.LocalizationFunctions")
local SingletonGetters          = requireFW("src.app.utilities.SingletonGetters")
local SkillDataAccessors        = requireFW("src.app.utilities.SkillDataAccessors")
local SkillDescriptionFunctions = requireFW("src.app.utilities.SkillDescriptionFunctions")
local WarFieldManager           = requireFW("src.app.utilities.WarFieldManager")
local WebSocketManager          = requireFW("src.app.utilities.WebSocketManager")
local Actor                     = requireFW("src.global.actors.Actor")

local string, table    = string, table
local getLocalizedText = LocalizationFunctions.getLocalizedText

local ACTION_CODE_ACTIVATE_SKILL = ActionCodeFunctions.getActionCode("ActionActivateSkill")
local ACTION_CODE_DECLARE_SKILL  = ActionCodeFunctions.getActionCode("ActionDeclareSkill")
local SKILL_DECLARATION_COST     = SkillDataAccessors.getSkillDeclarationCost()

--------------------------------------------------------------------------------
-- The util functions.
--------------------------------------------------------------------------------
local function generateSkillInfoText(self)
    local modelWar   = self.m_ModelWar
    local stringList = {string.format("%s: %d%%    %s: %s    %s: %s    %s: %s",
        getLocalizedText(14, "EnergyGainModifier"),     modelWar:getEnergyGainModifier(),
        getLocalizedText(14, "EnablePassiveSkill"),     getLocalizedText(14, (modelWar:isPassiveSkillEnabled())      and ("Yes") or ("No")),
        getLocalizedText(14, "EnableActiveSkill"),      getLocalizedText(14, (modelWar:isActiveSkillEnabled())       and ("Yes") or ("No")),
        getLocalizedText(14, "EnableSkillDeclaration"), getLocalizedText(14, (modelWar:isSkillDeclarationEnabled())  and ("Yes") or ("No"))
    )}

    SingletonGetters.getModelPlayerManager(modelWar):forEachModelPlayer(function(modelPlayer, playerIndex)
        stringList[#stringList + 1] = string.format("%s %d: %s    %s: %d    %s: %s\n%s",
            getLocalizedText(65, "Player"), playerIndex, modelPlayer:getNickname(),
            getLocalizedText(22, "CurrentEnergy"), modelPlayer:getEnergy(),
            getLocalizedText(22, "DeclareSkill"),  getLocalizedText(22, modelPlayer:isSkillDeclared() and "Yes" or "No"),
            SkillDescriptionFunctions.getBriefDescription(modelPlayer:getModelSkillConfiguration())
        )
    end)

    return table.concat(stringList, "\n--------------------\n")
end

local function generateSkillDetailText(skillID, isActiveSkill)
    local textList = {
        string.format("%s: %s\n%s / %s / %s",
            getLocalizedText(5, skillID), getLocalizedText(23, skillID),
            getLocalizedText(22, "Level"), getLocalizedText(22, "EnergyCost"), getLocalizedText(22, "Modifier")
        ),
    }

    local skillData         = SkillDataAccessors.getSkillData(skillID)
    local modifierUnit      = skillData.modifierUnit
    local pointsFieldName   = (isActiveSkill) and ("pointsActive")   or ("pointsPassive")
    local modifierFieldName = (isActiveSkill) and ("modifierActive") or ("modifierPassive")
    for level, levelData in ipairs(skillData.levels) do
        textList[#textList + 1] = string.format("%d        %d        %s",
            level, levelData[pointsFieldName], (levelData[modifierFieldName]) and ("" .. levelData[modifierFieldName] .. modifierUnit) or ("--" .. modifierUnit)
        )
    end

    return table.concat(textList, "\n")
end

local function generateActivateSkillConfirmationText(skillID, skillLevel, isActiveSkill)
    local skillData      = SkillDataAccessors.getSkillData(skillID)
    local modifierUnit   = skillData.modifierUnit
    local levelData      = skillData.levels[skillLevel]
    local modifier       = (isActiveSkill) and (levelData.modifierActive) or (levelData.modifierPassive)
    local energyCost     = (isActiveSkill) and (levelData.pointsActive)   or (levelData.pointsPassive)

    return string.format("%s\n%s %s%d\n%s: %d   %s: %s",
        (isActiveSkill) and (getLocalizedText(22, "ConfirmationActiveSkill")) or (getLocalizedText(22, "ConfirmationResearchSkill")),
        getLocalizedText(5, skillID), getLocalizedText(22, "Level"), skillLevel,
        getLocalizedText(22, "EnergyCost"), energyCost, getLocalizedText(22, "Modifier"), (modifier) and ("" .. modifier .. modifierUnit) or ("--" .. modifierUnit)
    )
end

--------------------------------------------------------------------------------
-- The callback functions on events.
--------------------------------------------------------------------------------
local function onEvtIsWaitingForServerResponse(self, event)
    self.m_IsWaitingForServerResponse = event.waiting
end

--------------------------------------------------------------------------------
-- The functions for sending actions.
--------------------------------------------------------------------------------
local function sendActionActivateSkill(warID, actionID, skillID, skillLevel, isActiveSkill)
    WebSocketManager.sendAction({
        actionCode    = ACTION_CODE_ACTIVATE_SKILL,
        warID         = warID,
        actionID      = actionID,
        skillID       = skillID,
        skillLevel    = skillLevel,
        isActiveSkill = isActiveSkill,
    })
end

local function sendActionDeclareSkill(warID, actionID)
    WebSocketManager.sendAction({
        actionCode  = ACTION_CODE_DECLARE_SKILL,
        warID       = warID,
        actionID    = actionID,
    })
end

local function cleanupAfterSendAction(modelWar)
    SingletonGetters.getModelMessageIndicator(modelWar):showPersistentMessage(getLocalizedText(80, "TransferingData"))
    SingletonGetters.getScriptEventDispatcher(modelWar):dispatchEvent({
        name    = "EvtIsWaitingForServerResponse",
        waiting = true,
    })
    SingletonGetters.getModelWarCommandMenu(modelWar):setEnabled(false)
end

--------------------------------------------------------------------------------
-- The dynamic items generators.
--------------------------------------------------------------------------------
local setStateActivateActiveSkill
local setStateChooseActiveSkillLevel
local setStateChoosePassiveSkillLevel
local setStateMain
local setStateResearchPassiveSkill

local function generateItemsSkillLevels(self, skillID, isActiveSkill)
    local modelWar   = self.m_ModelWar
    local warID           = SingletonGetters.getWarId(modelWar)
    local actionID        = SingletonGetters.getActionId(modelWar) + 1
    local modelConfirmBox = SingletonGetters.getModelConfirmBox(modelWar)
    local _, modelPlayer  = SingletonGetters.getModelPlayerManager(modelWar):getPlayerIndexLoggedIn()
    local energy          = modelPlayer:getEnergy()
    local skillData       = SkillDataAccessors.getSkillData(skillID)
    local minLevel        = (isActiveSkill) and (skillData.minLevelActive) or (skillData.minLevelPassive)
    local maxLevel        = (isActiveSkill) and (skillData.maxLevelActive) or (skillData.maxLevelPassive)
    local pointsFieldName = (isActiveSkill) and ("pointsActive")           or ("pointsPassive")

    local items            = {}
    local hasAvailableItem = false
    for level = minLevel, maxLevel do
        local isAvailable = skillData.levels[level][pointsFieldName] <= energy
        hasAvailableItem  = hasAvailableItem or isAvailable

        items[#items + 1] = {
            name        = getLocalizedText(22, "Level") .. level,
            isAvailable = isAvailable,
            callback    = function()
                modelConfirmBox:setConfirmText(generateActivateSkillConfirmationText(skillID, level, isActiveSkill))
                    :setOnConfirmYes(function()
                        sendActionActivateSkill(warID, actionID, skillID, level, isActiveSkill)
                        cleanupAfterSendAction(modelWar)
                        modelConfirmBox:setEnabled(false)
                    end)
                    :setEnabled(true)
            end,
        }
    end

    return items, hasAvailableItem
end

local function generateItemsForStateMain(self)
    local modelWar     = self.m_ModelWar
    local playerIndexInTurn = SingletonGetters.getModelTurnManager(modelWar):getPlayerIndex()
    if ((playerIndexInTurn ~= SingletonGetters.getPlayerIndexLoggedIn(modelWar)) or
        (self.m_IsWaitingForServerResponse))                                          then
        return {
            self.m_ItemSkillInfo,
            self.m_ItemCostListPassiveSkill,
            self.m_ItemCostListActiveSkill,
        }
    else
        local modelPlayer = SingletonGetters.getModelPlayerManager(modelWar):getModelPlayer(playerIndexInTurn)
        local items       = {}
        if (modelWar:isPassiveSkillEnabled()) then
            items[#items + 1] = self.m_ItemResearchPassiveSkill
        end
        if ((modelWar:isSkillDeclarationEnabled()) and (modelWar:isActiveSkillEnabled()) and (not modelPlayer:isSkillDeclared()) and (modelPlayer:getEnergy() >= SKILL_DECLARATION_COST)) then
            items[#items + 1] = self.m_ItemDeclareSkill
        end
        if ((modelWar:isActiveSkillEnabled()) and
            ((modelPlayer:canActivateSkill() or (not modelWar:isSkillDeclarationEnabled())))) then
            items[#items + 1] = self.m_ItemActivateActiveSkill
        end
        items[#items + 1] = self.m_ItemSkillInfo
        items[#items + 1] = self.m_ItemCostListPassiveSkill
        items[#items + 1] = self.m_ItemCostListActiveSkill

        return items
    end
end

local function generateItemsForStateActivateSkill(self)
    local items = {}
    for _, skillID in ipairs(SkillDataAccessors.getSkillCategory("SkillsActive")) do
        local subItems, hasAvailableSubItem = generateItemsSkillLevels(self, skillID, true)
        items[#items + 1] = {
            name        = getLocalizedText(5, skillID),
            isAvailable = hasAvailableSubItem,
            callback    = function()
                setStateChooseActiveSkillLevel(self, skillID, subItems)
            end,
        }
    end

    return items
end

local function generateItemsForStateResearchPassiveSkill(self)
    local items = {}
    for _, skillID in ipairs(SkillDataAccessors.getSkillCategory("SkillsPassive")) do
        local subItems, hasAvailableSubItem = generateItemsSkillLevels(self, skillID, false)
        items[#items + 1] = {
            name        = getLocalizedText(5, skillID),
            isAvailable = hasAvailableSubItem,
            callback    = function()
                setStateChoosePassiveSkillLevel(self, skillID, subItems)
            end,
        }
    end

    return items
end

--------------------------------------------------------------------------------
-- The state setters.
--------------------------------------------------------------------------------
setStateActivateActiveSkill = function(self)
    self.m_State = "stateActivateActiveSkill"

    local _, modelPlayer = SingletonGetters.getModelPlayerManager(self.m_ModelWar):getPlayerIndexLoggedIn()
    self.m_View:setMenuItems(generateItemsForStateActivateSkill(self))
        :setMenuTitleText(getLocalizedText(22, "ActivateSkill"))
        :setOverviewText(string.format("%s: %d\n\n%s", getLocalizedText(22, "CurrentEnergy"), modelPlayer:getEnergy(), self.m_TextActiveSkillOverview))
end

setStateChooseActiveSkillLevel = function(self, skillID, menuItemsForStateChooseActiveSkillLevel)
    self.m_State = "stateChooseActiveSkillLevel"
    self.m_View:setMenuItems(menuItemsForStateChooseActiveSkillLevel)
        :setOverviewText(generateSkillDetailText(skillID, true))
end

setStateChoosePassiveSkillLevel = function(self, skillID, menuItems)
    self.m_State = "stateChoosePassiveSkillLevel"
    self.m_View:setMenuItems(menuItems)
        :setOverviewText(generateSkillDetailText(skillID, false))
end

setStateMain = function(self)
    self.m_State = "stateMain"
    self.m_View:setMenuItems(generateItemsForStateMain(self))
        :setMenuTitleText(getLocalizedText(22, "SkillInfo"))
        :setOverviewText(generateSkillInfoText(self))
end

setStateResearchPassiveSkill = function(self)
    self.m_State = "stateResearchPassiveSkill"
    self.m_View:setMenuItems(generateItemsForStateResearchPassiveSkill(self))
        :setMenuTitleText(getLocalizedText(22, "ResearchPassiveSkill"))
        :setOverviewText(self.m_TextPassiveSkillOverview)
end

--------------------------------------------------------------------------------
-- The composition elements.
--------------------------------------------------------------------------------
local function initItemActivateActiveSkill(self)
    self.m_ItemActivateActiveSkill = {
        name     = getLocalizedText(22, "ActivateSkill"),
        callback = function()
            setStateActivateActiveSkill(self)
        end,
    }
end

local function initItemDeclareSkill(self)
    self.m_ItemDeclareSkill = {
        name     = getLocalizedText(22, "DeclareSkill"),
        callback = function()
            local modelWar   = self.m_ModelWar
            local modelConfirmBox = SingletonGetters.getModelConfirmBox(modelWar)
            modelConfirmBox:setConfirmText(getLocalizedText(22, "ConfirmationDeclareSkill"))
                :setOnConfirmYes(function()
                    sendActionDeclareSkill(SingletonGetters.getWarId(modelWar), SingletonGetters.getActionId(modelWar) + 1)
                    cleanupAfterSendAction(modelWar)
                    modelConfirmBox:setEnabled(false)
                end)
                :setEnabled(true)
        end,
    }
end

local function initItemCostListActiveSkill(self)
    self.m_ItemCostListActiveSkill = {
        name     = getLocalizedText(22, "EffectListActiveSkill"),
        callback = function()
            self.m_View:setOverviewText(self.m_TextActiveSkillOverview)
        end,
    }
end

local function initItemCostListPassiveSkill(self)
    self.m_ItemCostListPassiveSkill = {
        name     = getLocalizedText(22, "EffectListPassiveSkill"),
        callback = function()
            self.m_View:setOverviewText(self.m_TextPassiveSkillOverview)
        end,
    }
end

local function initItemResearchPassiveSkill(self)
    self.m_ItemResearchPassiveSkill = {
        name     = getLocalizedText(22, "ResearchPassiveSkill"),
        callback = function()
            setStateResearchPassiveSkill(self)
        end,
    }
end

local function initItemSkillInfo(self)
    self.m_ItemSkillInfo = {
        name     = getLocalizedText(22, "SkillInfo"),
        callback = function()
            self.m_View:setOverviewText(generateSkillInfoText(self))
        end
    }
end

local function initTextActiveSkillOverview(self)
    local textList = {}
    for _, skillID in ipairs(SkillDataAccessors.getSkillCategory("SkillsActive")) do
        textList[#textList + 1] = generateSkillDetailText(skillID, true)
    end

    textList[#textList + 1] = getLocalizedText(22, "HelpForActiveSkill")

    self.m_TextActiveSkillOverview = table.concat(textList, "\n\n")
end

local function initTextPassiveSkillOverview(self)
    local textList = {}
    for _, skillID in ipairs(SkillDataAccessors.getSkillCategory("SkillsPassive")) do
        textList[#textList + 1] = generateSkillDetailText(skillID, false)
    end

    textList[#textList + 1] = getLocalizedText(22, "HelpForPassiveSkill")

    self.m_TextPassiveSkillOverview = table.concat(textList, "\n\n")
end

--------------------------------------------------------------------------------
-- The constructor and initializers.
--------------------------------------------------------------------------------
function ModelSkillConfiguratorForOnline:ctor()
    initItemActivateActiveSkill( self)
    initItemCostListActiveSkill( self)
    initItemCostListPassiveSkill(self)
    initItemDeclareSkill(        self)
    initItemResearchPassiveSkill(self)
    initItemSkillInfo(           self)
    initTextActiveSkillOverview( self)
    initTextPassiveSkillOverview(self)

    return self
end

function ModelSkillConfiguratorForOnline:setCallbackOnButtonBackTouched(callback)
    self.m_OnButtonBackTouched = callback

    return self
end

function ModelSkillConfiguratorForOnline:onStartRunning(modelWar)
    self.m_ModelWar = modelWar
    SingletonGetters.getScriptEventDispatcher(modelWar)
        :addEventListener("EvtIsWaitingForServerResponse", self)

    return self
end

function ModelSkillConfiguratorForOnline:onEvent(event)
    local eventName = event.name
    if (eventName == "EvtIsWaitingForServerResponse") then onEvtIsWaitingForServerResponse(self, event)
    end

    return self
end

--------------------------------------------------------------------------------
-- The public functions.
--------------------------------------------------------------------------------
function ModelSkillConfiguratorForOnline:isEnabled()
    return self.m_IsEnabled
end

function ModelSkillConfiguratorForOnline:setEnabled(enabled)
    self.m_IsEnabled = enabled
    if (enabled) then
        setStateMain(self)
    end

    if (self.m_View) then
        self.m_View:setVisible(enabled)
    end

    return self
end

function ModelSkillConfiguratorForOnline:onButtonBackTouched()
    local state = self.m_State
    if     (state == "stateMain")                    then self.m_OnButtonBackTouched()
    elseif (state == "stateActivateActiveSkill")     then setStateMain(self)
    elseif (state == "stateChooseActiveSkillLevel")  then setStateActivateActiveSkill(self)
    elseif (state == "stateChoosePassiveSkillLevel") then setStateResearchPassiveSkill(self)
    elseif (state == "stateResearchPassiveSkill")    then setStateMain(self)
    else                                                  error("ModelSkillConfiguratorForOnline:onButtonBackTouched() invalid state: " .. (state or ""))
    end

    return self
end

return ModelSkillConfiguratorForOnline
