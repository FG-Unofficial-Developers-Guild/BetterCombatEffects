--  	Author: Ryan Hagelstrom
--	  	Copyright © 2021-2023
--	  	This work is licensed under a Creative Commons Attribution-ShareAlike 4.0 International License.
--	  	https://creativecommons.org/licenses/by-sa/4.0/
-- luacheck: globals EffectManagerBCE
------------------ ORIGINALS ------------------

local addEffect = nil;
------------------ END ORIGINALS ------------------
--
-- CONSOLIDATED EFFECT QUERY HELPERS
-- 		NOTE: PRELIMINARY FOR VISION SUPPORT
--		NOTE 2: NEEDS CONDITIONAL SUPPORT FOR GENERAL PURPOSE USE
--
-- EFFECT TYPE PARAMETERS
-- 		bIgnoreExpire = true/false (default = false)
--		bIgnoreTarget = true/false (default = false)
--		bIgnoreDisabledCheck = true/false (default = false)
--      bIgnoreOtherFilter = true/false (default = false)
-- 		bOneShot = true/false (default = false)
-- 		bDamageFilter = true/false (default = false)
-- 		bConditionFilter = true/false (default = false)

local _tEffectCompTypes = {};

------------------ CUSTOM BCE FUNTION HOOKS ------------------
local aCustomMatchEffectHandlers = {};
local aCustomPreAddEffectHandlers = {};
local aCustomPostAddEffectHandlers = {};

local getEffectsByType = nil;
------------------ END CUSTOM BCE FUNTION HOOKS ------------------

function onInit()
    addEffect = EffectManager.addEffect;
    getEffectsByType = EffectManager.getEffectsByType;

    EffectManager.registerEffectVar('sChangeState', {sDBType = 'string', sDBField = 'changestate', sDisplay = '[%s]'})

    -- for some reason in 5E, lights can't be turned off when we override this
    -- LIGHT is run though  EffectManager.getEffectsbyType and if we override it, then we have problems
    -- If we don't override it resolves and I don't think we care if it is overridden if we are running a
    -- spported ruleset because we have a RulesetManager to select which version to call.

    EffectManager.addEffect = EffectManagerBCE.customAddEffectPre;
    if User.getRulesetName() ~= '5E' then
        EffectManager.getEffectsByType = customGetEffectsByType;
    end

    if Session.IsHost then
        EffectManagerBCE.initEffectHandlers();
        CombatManager.setCustomDeleteCombatantHandler(unregisterCombatant);
        DB.addHandler('combattracker.list.*.effects.*.changestate', 'onUpdate', stateModified);
        DB.addHandler('combattracker.list.*.effects.*.changestate', 'onDelete', deleteState);
    end
end

function onClose()
    EffectManager.addEffect = addEffect;
    if User.getRulesetName() ~= '5E' then
        EffectManager.getEffectsByType = getEffectsByType;
    end
    if Session.IsHost then
        EffectManagerBCE.deleteEffectHandlers();
        DB.removeHandler('combattracker.list.*.effects.*.changestate', 'onUpdate', stateModified);
        DB.removeHandler('combattracker.list.*.effects.*.changestate', 'onDelete', deleteState);
    end
end


------------------ OVERRIDES ------------------
function customGetEffectsByType(rActor, sEffectCompType, rFilterActor, bTargetedOnly)
    if not rActor then
        return {};
    end
    local tResults = {};
    local tEffectCompParams = EffectManagerBCE.getEffectCompType(sEffectCompType);

    -- Iterate through effects
    local aEffects;
    if TurboManager then
        aEffects = TurboManager.getMatchedEffects(rActor, sEffectCompType);
    else
        aEffects = DB.getChildList(ActorManager.getCTNode(rActor), 'effects');
    end

    for _, v in pairs(aEffects) do
        -- Check active
        local nActive = DB.getValue(v, 'isactive', 0);
        local bActive = (tEffectCompParams.bIgnoreExpire and (nActive == 1)) or (not tEffectCompParams.bIgnoreExpire and (nActive ~= 0)) or
                            (tEffectCompParams.bIgnoreDisabledCheck and (nActive == 0));
        if bActive or nActive ~= 0 then
            -- If effect type we are looking for supports targets, then check targeting
            local bTargetMatch;
            if tEffectCompParams.bIgnoreTarget then
                bTargetMatch = true;
            else
                local bTargeted = EffectManager.isTargetedEffect(v);
                if bTargeted then
                    bTargetMatch = EffectManager.isEffectTarget(v, rFilterActor);
                else
                    bTargetMatch = not bTargetedOnly;
                end
            end

            if bTargetMatch then
                local sLabel = DB.getValue(v, 'label', '');
                local aEffectComps = EffectManager.parseEffect(sLabel);

                -- Look for type/subtype match
                local nMatch = 0;
                for kEffectComp, sEffectComp in ipairs(aEffectComps) do
                    local rEffectComp = EffectManager.parseEffectCompSimple(sEffectComp);
                    if rEffectComp.type == sEffectCompType or rEffectComp.original == sEffectCompType then
                        nMatch = kEffectComp;
                        rEffectComp.sEffectNode = DB.getPath(v);
                        if nActive == 1 or (tEffectCompParams.bIgnoreDisabledCheck and (nActive == 0)) then
                            table.insert(tResults, rEffectComp);
                        end
                    end
                end -- END EFFECT COMPONENT LOOP

                -- Remove one shot effects
                if (nMatch > 0) and not tEffectCompParams.bIgnoreExpire then
                    if nActive == 2 then
                        DB.setValue(v, 'isactive', 'number', 1);
                    else
                        local sApply = DB.getValue(v, 'apply', '');
                        if sApply == 'action' then
                            EffectManager.notifyExpire(v, 0);
                        elseif sApply == 'roll' then
                            EffectManager.notifyExpire(v, 0, true);
                        elseif sApply == 'single' or tEffectCompParams.bOneShot then
                            EffectManager.notifyExpire(v, nMatch, true);
                        elseif bDisableUse and sApply == 'duse' then
                            BCEManager.modifyEffect(v.sEffectNode, 'Deactivate');
                        end
                    end
                end
            end -- END TARGET CHECK
        end -- END ACTIVE CHECK
    end -- END EFFECT LOOP

    -- RESULTS
    return tResults;
end

function customAddEffectPre(sUser, sIdentity, nodeCT, rNewEffect, bShowMsg)
    BCEManager.chat('Add Effect Pre: ', rNewEffect.sName);
    if not nodeCT or not rNewEffect or not rNewEffect.sName then
        return addEffect(sUser, sIdentity, nodeCT, rNewEffect, bShowMsg);
    end
    if EffectManagerBCE.onCustomPreAddEffect(sUser, sIdentity, nodeCT, rNewEffect, bShowMsg) then
        return true;
    end
    addEffect(sUser, sIdentity, nodeCT, rNewEffect, bShowMsg);
    local nodeEffect;
    if (not rNewEffect.sSource) then
        rNewEffect.sSource = '';
    end
    if (not rNewEffect.sChangeState) then
        rNewEffect.sChangeState = '';
    end
    if (not rNewEffect.sApply) then
        rNewEffect.sApply = '';
    end
    for _, v in ipairs(DB.getChildList(nodeCT, 'effects')) do
        if (DB.getValue(v, 'label', '') == rNewEffect.sName) and (DB.getValue(v, 'init', 0) == rNewEffect.nInit) and
            (DB.getValue(v, 'duration', 0) == rNewEffect.nDuration) and (DB.getValue(v, 'source_name', '') == rNewEffect.sSource) and
            (DB.getValue(v, 'apply', '') == rNewEffect.sApply) and (DB.getValue(v, 'changestate', '') == rNewEffect.sChangeState) then
            nodeEffect = v;
            DB.addHandler(DB.getPath(nodeEffect), 'onDelete', expireAdd);
            EffectManagerBCE.addChangeStateHandler(nodeCT, nodeEffect);
            EffectManagerBCE.onCustomPostAddEffect(nodeCT, nodeEffect);
            break
        end
    end
end
------------------ END OVERRIDES ------------------
--
-- CONSOLIDATED EFFECT QUERY HELPERS
-- 		NOTE: PRELIMINARY FOR VISION SUPPORT
--		NOTE 2: NEEDS CONDITIONAL SUPPORT FOR GENERAL PURPOSE USE
--
-- EFFECT TYPE PARAMETERS
-- 		bIgnoreExpire = true/false (default = false)
--		bIgnoreTarget = true/false (default = false)
--		bIgnoreDisabledCheck = true/false (default = false)
-- 		bIgnoreOtherFilter = true/false (default = false)
-- 		bOneShot = true/false (default = false)
--      bDamageFilter = true/false (default = false)
--      bConditionFilter = true/false (default = false)

function registerEffectCompType(sEffectCompType, tParams)
    _tEffectCompTypes[sEffectCompType] = tParams;
end

function getEffectCompType(sEffectCompType)
    local aReturn = {};
    if _tEffectCompTypes[sEffectCompType] then
        aReturn = _tEffectCompTypes[sEffectCompType];
    end

    return aReturn;
end

-- accepts database path or databasenode
function getLabelShort(nodeEffect)
    if type(nodeEffect) == 'string' then
        nodeEffect = DB.findNode(nodeEffect);
    end
    local sLabel = DB.getValue(nodeEffect, 'label', '');
    local tParseEffect = EffectManager.parseEffect(sLabel);
    return StringManager.trim(tParseEffect[1]);
end

function initEffectHandlers()
    local ctEntries = CombatManager.getCombatantNodes();
    for _, nodeCT in pairs(ctEntries) do
        for _, nodeEffect in ipairs(DB.getChildList(nodeCT, 'effects')) do
            DB.addHandler(DB.getPath(nodeEffect), 'onDelete', expireAdd);
            EffectManagerBCE.addChangeStateHandler(nodeCT, nodeEffect);
        end
        DB.addHandler(DB.getPath(nodeCT, 'effects.*.label'), 'onAdd', expireAddHelper);
    end
end

function deleteEffectHandlers()
    local ctEntries = CombatManager.getCombatantNodes();
    for _, nodeCT in pairs(ctEntries) do
        for _, nodeEffect in ipairs(DB.getChildList(nodeCT, 'effects')) do
            DB.removeHandler(DB.getPath(nodeEffect), 'onDelete', expireAdd);
            EffectManagerBCE.deleteChangeStateHandler(nodeCT, nodeEffect);
        end
        DB.removeHandler(DB.getPath(nodeCT, 'effects.*.label'), 'onAdd', expireAdd);
    end
end

function expireAddHelper(nodeLabel)
    DB.removeHandler(DB.getPath(nodeLabel), 'onAdd', expireAddHelper);
    DB.addHandler(DB.getPath(DB.getChild(nodeLabel, '..')), 'onDelete', expireAdd);
end

function expireAdd(nodeEffect)
    BCEManager.chat('expireAdd: ');
    local sLabel = DB.getValue(nodeEffect, 'label', '', '');
    if sLabel:match('EXPIREADD') then
        local sActor = DB.getPath(DB.getChild(nodeEffect, '...'));
        local nodeCT = DB.findNode(sActor);
        local sSource = DB.getValue(nodeEffect, 'source_name', '');
        local sourceNode = nodeCT;
        if sSource ~= '' then
            sourceNode = DB.findNode(sSource);
        end
        local aEffectComps = EffectManager.parseEffect(sLabel);
        for _, sEffectComp in ipairs(aEffectComps) do
            local tEffectComp = EffectManager.parseEffectCompSimple(sEffectComp);
            if tEffectComp.type == 'EXPIREADD' then
                BCEManager.notifyAddEffect(nodeCT, sourceNode, StringManager.combine(' ', unpack(tEffectComp.remainder)));
                break
            end
        end
    end
    DB.removeHandler(DB.getPath(nodeEffect), 'onDelete', expireAdd);
end

------------------ CUSTOM BCE FUNTION HOOKS ------------------
function setCustomMatchEffect(f)
    table.insert(aCustomMatchEffectHandlers, f);
end

function removeCustomMatchEffect(f)
    for kCustomMatchEffect, fCustomMatchEffect in ipairs(aCustomMatchEffectHandlers) do
        if fCustomMatchEffect == f then
            table.remove(aCustomMatchEffectHandlers, kCustomMatchEffect);
            return false; -- success
        end
    end
    return true;
end

function onCustomMatchEffect(sEffect)
    for _, fMatchEffect in ipairs(aCustomMatchEffectHandlers) do
        if fMatchEffect(sEffect) == true then
            return true;
        end
    end
    return false; -- success
end

function setCustomPreAddEffect(f)
    table.insert(aCustomPreAddEffectHandlers, f);
end

function removeCustomPreAddEffect(f)
    for kCustomPreAddEffect, fCustomPreAddEffect in ipairs(aCustomPreAddEffectHandlers) do
        if fCustomPreAddEffect == f then
            table.remove(aCustomPreAddEffectHandlers, kCustomPreAddEffect);
            return false; -- success
        end
    end
    return true;
end

function onCustomPreAddEffect(sUser, sIdentity, nodeCT, rNewEffect, bShowMsg)
    -- do this backwards from order added. Need to account for string changes in the effect
    -- from things like [STR] before we do any dice roll handlers
    for i = #aCustomPreAddEffectHandlers, 1, -1 do
        if aCustomPreAddEffectHandlers[i](sUser, sIdentity, nodeCT, rNewEffect, bShowMsg) == true then
            return true;
        end
    end
    return false; -- success
end

function setCustomPostAddEffect(f)
    table.insert(aCustomPostAddEffectHandlers, f);
end

function removeCustomPostAddEffect(f)
    for kCustomPostAddEffect, fCustomPostAddEffect in ipairs(aCustomPostAddEffectHandlers) do
        if fCustomPostAddEffect == f then
            table.remove(aCustomPostAddEffectHandlers, kCustomPostAddEffect);
            return false; -- success
        end
    end
    return true;
end

function onCustomPostAddEffect(nodeActor, nodeEffect)
    for _, fPostAddEffect in ipairs(aCustomPostAddEffectHandlers) do
        fPostAddEffect(nodeActor, nodeEffect);
    end
end
------------------ CUSTOM BCE FUNTION HOOKS ------------------
-- nodeCTPath execute the change state on this nodes turn
-- [nodeCTPath][state/operation][effectPath]
local tChangeState = {};
local tChangeStateLookup = {};
-- as ={}, ds = {}, rs = {}, ae = {}, de = {}, re = {}, sas ={}, sds = {}, srs = {}, sae = {}, sde = {}, sre = {}
-- [state/operation][effectPath]
local tChangeStateAny = {ats = {}, dts = {}, rts = {}};
local tChangeStateAnyLookup = {};
------------------ CHANGE STATE ------------------

function addChangeStateHandler(nodeCT, nodeEffect)
    BCEManager.chat('addChangeStateHandler: ');
    local sNode = DB.getPath(nodeCT);
    if not tChangeState[sNode] then
        tChangeState[sNode] = {};
    end
    local sChangeState = DB.getPath(nodeEffect, 'changestate');
    local sValue = DB.getValue(nodeEffect, 'changestate', '');
    if sValue == '' or sValue == 'as' or sValue == 'ae' or sValue == 'sas' or sValue == 'sae' then
        local nDuration = DB.getValue(nodeEffect, 'duration', 0);
        if nDuration ~= 0 then
            DB.setValue(nodeEffect, 'duration', 'number', nDuration+1);
        end
    end

    EffectManagerBCE.stateModified(DB.findNode(sChangeState));
end

function deleteState(nodeCS)
    BCEManager.chat('deleteState: ');
    local sEffect = DB.getPath(DB.getChild(nodeCS, '..'), '');
    local sActor = DB.getPath(DB.getChild(nodeCS, '....'), '');
    if tChangeStateLookup[sEffect] then
        tChangeState[sActor][tChangeStateLookup[sEffect]][sEffect] = nil;
    end
    if tChangeStateAny[tChangeStateAnyLookup[sEffect]] then
        tChangeStateAny[tChangeStateAnyLookup[sEffect]][sEffect] = nil;
    end
    if tChangeStateAnyLookup.sEffect then
        tChangeStateAnyLookup.sEffect = nil;
    end
end

function deleteChangeStateHandler(nodeCT, nodeEffect)
    BCEManager.chat('deleteChangeStateHandler: ');
    DB.removeHandler(DB.getPath(nodeEffect, 'changestate'), 'onUpdate', deleteStateModified);
end

function stateModified(nodeCS)
    BCEManager.chat('stateModified: ');
    if not nodeCS then
        return;
    end
    local sValue = DB.getValue(nodeCS, '', '');
    local nodeEffect = DB.getChild(nodeCS, '..')
    local sEffect = DB.getPath(nodeEffect, '');
    local sActor = DB.getPath(DB.getChild(nodeCS, '....'), '');
    if sValue == 'rts' or sValue == 'rs'or sValue == 're' or sValue == 'srs' or sValue == 'sre' then
        local nDuration = DB.getValue(nodeEffect, 'duration', 0);
        if nDuration ~= 0 then
            DB.setValue(nodeEffect, 'duration', 'number', nDuration+1);
        end
    end
    if sValue == '' or sValue == 'as' or sValue == 'ae' or sValue == 'sas' or sValue == 'sae' then
        local nDuration = DB.getValue(nodeEffect, '.duration', 0);
        if nDuration ~= 0 then
            DB.setValue(nodeEffect, 'duration', 'number', nDuration-1);
        end
    end
    if tChangeStateLookup[sEffect] then
        tChangeState[sActor][tChangeStateLookup[sEffect]][sEffect] = nil;
    end
    if tChangeStateAnyLookup.sEffect then
        tChangeStateAnyLookup.sEffect = nil;
    end
    if tChangeStateAny[tChangeStateAnyLookup[sEffect]] then
        tChangeStateAny[tChangeStateAnyLookup[sEffect]][sEffect] = nil;
    end
    if sValue == 'ats' or sValue == 'dts' or sValue == 'rts' then
        tChangeStateAny[sValue][sEffect] = true;
        tChangeStateAnyLookup[sEffect] = sValue;
    else
        if not tChangeState[sActor] then
            tChangeState[sActor] = {};
        end
        if sValue:match('^s') then
            local sSourceActor = DB.getValue(sEffect .. 'source_name', '');
            if sSourceActor ~= '' then
                sActor = sSourceActor;
            end
        end
        if sValue ~= '' and not tChangeState[sActor][sValue] then
            tChangeState[sActor][sValue] = {};
        end
        if sActor ~= '' and tChangeState[sActor] and tChangeState[sActor][tChangeStateLookup[sEffect]] then
            tChangeState[sActor][tChangeStateLookup[sEffect]][sEffect] = nil;
        end
        if sValue ~= '' then
            tChangeState[sActor][sValue][sEffect] = true;
            tChangeStateLookup[sEffect] = sValue;
        end
    end
end

function deleteStateModified(nodeCS)
    BCEManager.chat('deleteStateModified: ');
    local sValue = DB.getValue(nodeCS, '');
    if sValue ~= '' then
        local sEffect = DB.getPath(DB.getChild(nodeCS, '...'));
        if sValue == 'ats' or sValue == 'dts' or sValue == 'rts' then
            tChangeStateAny[sValue][sEffect] = nil;
            tChangeStateAnyLookup[sEffect] = nil;
        else
            local sActor = DB.getPath(DB.getChild(nodeCS, '....'));
            tChangeState[sActor][sValue][sEffect] = nil;
            tChangeStateLookup[sEffect] = nil;
        end
    end
end

function changeState(nodeCT, bStart)
    BCEManager.chat('changeState: ');
    EffectManagerBCE.activateState(nodeCT, bStart);
    EffectManagerBCE.deactivateState(nodeCT, bStart);
    EffectManagerBCE.removeState(nodeCT, bStart);
end

local aActivateStates = {'as', 'ae', 'sas', 'sae'};
local aDeactivateStates = {'ds', 'de', 'sds', 'sde'};
local aRemoveStates = {'rs', 're', 'srs', 'sre'};

function activateState(nodeCT, bStart)
    BCEManager.chat('activateState: ');
    local sPath = DB.getPath(nodeCT);
    if bStart and next(tChangeStateAny.ats) then
        for sEffect, _ in pairs(tChangeStateAny['ats']) do
            if DB.getValue(sEffect .. '.isactive', 100) ~= 1 then
                BCEManager.modifyEffect(sEffect, 'Activate');
            end
        end
    end
    for _, sState in ipairs(aActivateStates) do
        if tChangeState[sPath] and tChangeState[sPath][sState] then
            for sEffect, _ in pairs(tChangeState[sPath][sState]) do
                if bStart and (sState == 'as' or sState == 'sas') then
                    if DB.getValue(sEffect .. '.isactive', 100) ~= 1 then
                        BCEManager.modifyEffect(sEffect, 'Activate');
                    end
                elseif not bStart and (sState == 'ae' or sState == 'sae') then
                    if DB.getValue(sEffect .. '.isactive', 100) ~= 1 then
                        BCEManager.modifyEffect(sEffect, 'Activate');
                    end
                end
            end
        end
    end
end

function deactivateState(nodeCT, bStart)
    BCEManager.chat('deactivateState: ');
    local sPath = DB.getPath(nodeCT);
    if bStart and next(tChangeStateAny.dts) then
        for sEffect, _ in pairs(tChangeStateAny['dts']) do
            if DB.getValue(sEffect .. '.isactive', 100) ~= 0 then
                BCEManager.modifyEffect(sEffect, 'Deactivate');
            end
        end
    end
    for _, sState in ipairs(aDeactivateStates) do
        if tChangeState[sPath] and tChangeState[sPath][sState] then
            for sEffect, _ in pairs(tChangeState[sPath][sState]) do
                if bStart and (sState == 'ds' or sState == 'sds') then
                    if DB.getValue(sEffect .. '.isactive', 100) ~= 0 then
                        BCEManager.modifyEffect(sEffect, 'Deactivate');
                    end
                elseif not bStart and (sState == 'de' or sState ==  'sde') then
                    if DB.getValue(sEffect .. '.isactive', 100) ~= 0 then
                        BCEManager.modifyEffect(sEffect, 'Deactivate');
                    end
                end
            end
        end
    end
end

function removeState(nodeCT, bStart)
    BCEManager.chat('removeState: ');
    local sPath = DB.getPath(nodeCT);
    if bStart and next(tChangeStateAny.rts) then
        for sEffect, _ in pairs(tChangeStateAny['rts']) do
            if DB.getValue(sEffect .. '.duration', 0) == 1 then
                BCEManager.modifyEffect(sEffect, 'Remove');
            end
        end
    end
    for _, sState in ipairs(aRemoveStates) do
        if tChangeState[sPath] and tChangeState[sPath][sState] then
            for sEffect, _ in pairs(tChangeState[sPath][sState]) do
                if bStart and (sState == 'rs' or 'srs') then
                    if DB.getValue(sEffect .. '.duration', 0) == 1 then
                        BCEManager.modifyEffect(sEffect, 'Remove');
                    end
                elseif not bStart and (sState == 're' or sState ==  'sre') then
                    if DB.getValue(sEffect .. '.duration', 0) == 1 then
                        BCEManager.modifyEffect(sEffect, 'Remove');
                    end
                end
            end
        end
    end
end

function unregisterCombatant(nodeCT)
    BCEManager.chat('unregisterCombatant: ');
    tChangeState[DB.getPath(nodeCT)] = nil;
end
