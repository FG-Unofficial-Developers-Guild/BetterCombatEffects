--  	Author: Ryan Hagelstrom
--	  	Copyright © 2021
--	  	This work is licensed under a Creative Commons Attribution-ShareAlike 4.0 International License.
--	  	https://creativecommons.org/licenses/by-sa/4.0/

local bMadNomadCharSheetEffectDisplay = false
local bAutomaticSave = false
local restChar = nil
local getDamageAdjust = nil
local parseEffects = nil

function onInit()
	if User.getRulesetName() == "5E" then 
		if Session.IsHost then
			OptionsManager.registerOption2("ALLOW_DUPLICATE_EFFECT", false, "option_Better_Combat_Effects", 
			"option_Allow_Duplicate", "option_entry_cycler", 
			{ labels = "option_val_off", values = "off",
				baselabel = "option_val_on", baseval = "on", default = "on" });

			OptionsManager.registerOption2("CONSIDER_DUPLICATE_DURATION", false, "option_Better_Combat_Effects", 
			"option_Consider_Duplicate_Duration", "option_entry_cycler", 
			{ labels = "option_val_on", values = "on",
				baselabel = "option_val_off", baseval = "off", default = "off" });

			OptionsManager.registerOption2("RESTRICT_CONCENTRATION", false, "option_Better_Combat_Effects", 
			"option_Concentrate_Restrict", "option_entry_cycler", 
			{ labels = "option_val_on", values = "on",
				baselabel = "option_val_off", baseval = "off", default = "off" });
			OptionsManager.registerOption2("AUTOPARSE_EFFECTS", false, "option_Better_Combat_Effects", 
			"option_Autoparse_Effects", "option_entry_cycler", 
			{ labels = "option_val_on", values = "on",
				baselabel = "option_val_off", baseval = "off", default = "off" });
		end

		rest = CharManager.rest
		CharManager.rest = customRest
		getDamageAdjust = ActionDamage.getDamageAdjust
		ActionDamage.getDamageAdjust = customGetDamageAdjust
		parseEffects = PowerManager.parseEffects
		PowerManager.parseEffects = customParseEffects

		EffectsManagerBCE.setCustomProcessTurnStart(processEffectTurnStart5E)
		EffectsManagerBCE.setCustomProcessTurnEnd(processEffectTurnEnd5E)
		EffectsManagerBCE.setCustomPreAddEffect(addEffectPre5E)
		EffectsManagerBCE.setCustomPostAddEffect(addEffectPost5E)
		EffectsManagerBCE.setCustomProcessEffect(processEffect)
		EffectsManagerBCEDND.setProcessEffectOnDamage(onDamage)

		ActionsManager.registerResultHandler("savebce", onSaveRollHandler5E)
		ActionsManager.registerModHandler("savebce", onModSaveHandler)

		EffectManager.setCustomOnEffectAddIgnoreCheck(customOnEffectAddIgnoreCheck)
	
		aExtensions = Extension.getExtensions()
		for _,sExtension in ipairs(aExtensions) do
			tExtension = Extension.getExtensionInfo(sExtension)
			if (tExtension.name == "MNM Charsheet Effects Display") then
				bMadNomadCharSheetEffectDisplay = true
			end
			if (tExtension.name == "5E - Automatic Save Advantage") then
				bAutomaticSave = true
			end
			
		end
	end
end

function onClose()
	if User.getRulesetName() == "5E" then 
		CharManager.rest = rest
		ActionDamage.getDamageAdjust = getDamageAdjust
		PowerManager.parseEffects = parseEffects
		ActionsManager.unregisterResultHandler("savebce")
		ActionsManager.unregisterModHandler("savebce")
		EffectsManagerBCE.removeCustomProcessTurnStart(processEffectTurnStart5E)
		EffectsManagerBCE.removeCustomProcessTurnEnd(processEffectTurnEnd5E)
		EffectsManagerBCE.removeCustomPreAddEffect(addEffectPre5E)
		EffectsManagerBCE.removeCustomPostAddEffect(addEffectPost5E)
		EffectsManagerBCE.removeCustomProcessEffect(processEffect)

	end
end

function customOnEffectAddIgnoreCheck(nodeCT, rEffect)
	local sDuplicateMsg = nil; 
	sDuplicateMsg = EffectManager5E.onEffectAddIgnoreCheck(nodeCT, rEffect)
	local nodeEffectsList = nodeCT.createChild("effects")
	if not nodeEffectsList then
		return sDuplicateMsg
	end
	local bIgnoreDuration = OptionsManager.isOption("CONSIDER_DUPLICATE_DURATION", "off");
	if OptionsManager.isOption("ALLOW_DUPLICATE_EFFECT", "off")  and not rEffect.sName:match("STACK") then
		for k, nodeEffect in pairs(nodeEffectsList.getChildren()) do
			if (DB.getValue(nodeEffect, "label", "") == rEffect.sName) and
					(DB.getValue(nodeEffect, "init", 0) == rEffect.nInit) and
					(bIgnoreDuration or (DB.getValue(nodeEffect, "duration", 0) == rEffect.nDuration)) and
					(DB.getValue(nodeEffect,"source_name", "") == rEffect.sSource) then
				sDuplicateMsg = string.format("%s ['%s'] -> [%s]", Interface.getString("effect_label"), rEffect.sName, Interface.getString("effect_status_exists"))
				break
			end
		end
	end
	return sDuplicateMsg
end

function customRest(nodeActor, bLong, bMilestone)
	EffectsManagerBCEDND.customRest(nodeActor, bLong, nil)
	rest(nodeActor, bLong)
end

--Do sanity checks to see if we should process this effect any further
function processEffect(rSource, nodeEffect, sBCETag, rTarget, bIgnoreDeactive)
	local sEffect = DB.getValue(nodeEffect, "label", "")
	-- is there a conditional that prevents us from processing
	local aEffectComps = EffectManager.parseEffect(sEffect)
	for _,sEffectComp in ipairs(aEffectComps) do -- Check conditionals
		local rEffectComp = EffectManager.parseEffectCompSimple(sEffectComp)
		if rEffectComp.type == "IF" then
			if not EffectManager5E.checkConditional(rSource, nodeEffect, rEffectComp.remainder, rTarget) then
				return false
			end
		elseif rEffectComp.type == "IFT" then
			if not EffectManager5E.checkConditional(rSource, nodeEffect, rEffectComp.remainder, rTarget) then
				return false
			end
		end
	end	
	return true -- Everything looks good to continue processing
end

function processEffectTurnStart5E(sourceNodeCT, nodeCT, nodeEffect)
	local sEffect = DB.getValue(nodeEffect, "label", "")
	local sEffectSource = DB.getValue(nodeEffect, "source_name", "")
	local rTarget = ActorManager.resolveActor(nodeCT)
	local rSource = nil
	if rSourceEffect == nil then
		rSource = rTarget
	else
		rSource = ActorManager.resolveActor(sEffectSource)
	end
	
	if sourceNodeCT == nodeCT and EffectsManagerBCE.processEffect(rSource,nodeEffect,"SAVES",rTarget) then
		saveEffect(nodeEffect, sourceNodeCT, "Save")
	end
	return true
end


--function ManagerEffect5E.getEffectsByType(rActor, sEffectCompType, rFilterActor, bTargetedOnly)

function processEffectTurnEnd5E(sourceNodeCT, nodeCT, nodeEffect)
	local sEffect = DB.getValue(nodeEffect, "label", "")
	local sEffectSource = DB.getValue(nodeEffect, "source_name", "")
	local rTarget = ActorManager.resolveActor(nodeCT)
	local rSource = nil
	if rSourceEffect == nil then
		rSource = rTarget
	else
		rSource = ActorManager.resolveActor(sEffectSource)
	end
	
	if sourceNodeCT == nodeCT and EffectsManagerBCE.processEffect(rSource,nodeEffect,"SAVEE", rTarget) then
		EffectManager5E.getEffectsByType(rSource, "SAVEE", rTarget)
		saveEffect(nodeEffect, sourceNodeCT, "Save")
	end
	return true
end

function addEffectPre5E(sUser, sIdentity, nodeCT, rNewEffect, bShowMsg)
	-- Repalace effects with () that fantasygrounds will autocalc with [ ]
	local sSubMatch = rNewEffect.sName:match("%([%-H%d+]?%u+%)")
	local aReplace = {"PRF", "LVL"}
	for _,sClass in pairs(DataCommon.classes) do
		table.insert(aReplace, sClass:upper())	
	end
	for _,sAbility in pairs(DataCommon.abilities) do
		table.insert(aReplace, DataCommon.ability_ltos[sAbility]:upper())
	end
	for _,sTag in pairs(aReplace) do
		if sSubMatch:match(sTag) then
			sSubMatch = sSubMatch:gsub("%-", "%%%-")
			sSubMatch = sSubMatch:gsub("%(", "%%%[")
			sSubMatch = sSubMatch:gsub("%)", "]")
			rNewEffect.sName = rNewEffect.sName:gsub("%([%-H%d+]?%u+%)", sSubMatch)
			break
		end
	end
	local rActor = ActorManager.resolveActor(nodeCT)
	local rSource = nil
	if rNewEffect.sSource == nil or rNewEffect.sSource == "" then
		rSource = rActor
	else
		local nodeSource = DB.findNode(rNewEffect.sSource)
		rSource = ActorManager.resolveActor(nodeSource)		
	end

	rNewEffect.sName = EffectManager5E.evalEffect(rSource, rNewEffect.sName)
	replaceSaveDC(rNewEffect, rSource)

	if OptionsManager.isOption("RESTRICT_CONCENTRATION", "on") then
		local nDuration = rNewEffect.nDuration
		if rNewEffect.sUnits == "minute" then
			nDuration = nDuration*10
		end
		dropConcentration(rNewEffect, nDuration)
	end

	return true
end

function addEffectPost5E(sUser, sIdentity, nodeCT, rNewEffect)
	local rActor = ActorManager.resolveActor(nodeCT)
	for _,nodeEffect in pairs(DB.getChildren(nodeCT, "effects")) do
		if (DB.getValue(nodeEffect, "label", "") == rNewEffect.sName) and
			(DB.getValue(nodeEffect, "init", 0) == rNewEffect.nInit) and
			(DB.getValue(nodeEffect, "duration", 0) == rNewEffect.nDuration) and
			(DB.getValue(nodeEffect,"source_name", "") == rNewEffect.sSource) then
			local nodeSource = DB.findNode(rNewEffect.sSource)
			local rSource = ActorManager.resolveActor(nodeSource)
			local rTarget = rActor
			if EffectsManagerBCE.processEffect(rSource, nodeEffect, "SAVEA", rTarget) then
				saveEffect(nodeEffect, nodeCT, "Save")
				break
			end
			if EffectsManagerBCE.processEffect(rSource, nodeEffect, "REGENA", rTarget) then
				EffectsManagerBCEDND.applyOngoingRegen(rSource, rTarget, nodeEffect, true)
				break
			end
			if EffectsManagerBCE.processEffect(rSource, nodeEffect, "DMGA", rTarget) then
				EffectsManagerBCEDND.applyOngoingDamage(rSource, rTarget, nodeEffect, false, true)
				break
			end
		end
	end
	return true
end

function getDCEffectMod(nodeActor)
	local nDC = 0
	for _,nodeEffect in pairs(DB.getChildren(nodeActor, "effects")) do
		local sEffect = DB.getValue(nodeEffect, "label", "")
		local aEffectComps = EffectManager.parseEffect(sEffect)
		for _,sEffectComp in ipairs(aEffectComps) do
			local rEffectComp = EffectManager.parseEffectCompSimple(sEffectComp)
			if rEffectComp.type == "DC" and (DB.getValue(nodeEffect, "isactive", 0) == 1) then
				nDC = tonumber(rEffectComp.mod) or 0
				break
			end
		end
	end
	return nDC
end

function replaceSaveDC(rNewEffect, rActor)
	if (rNewEffect.sName:match("%[SDC]") or rNewEffect.sName:match("%(SDC%)")) and  
			(rNewEffect.sName:match("SAVEE") or 
			rNewEffect.sName:match("SAVES") or 
			rNewEffect.sName:match("SAVEA:") or
		    rNewEffect.sName:match("SAVEONDMG")) then
		local sNodeType, nodeActor = ActorManager.getTypeAndNode(rActor)
		local nSpellcastingDC = 0
		local nDC = getDCEffectMod(ActorManager.getCTNode(rActor))
		if sNodeType == "pc" then
			nSpellcastingDC = 8 +  ActorManager5E.getAbilityBonus(rActor, "prf") + nDC
			for _,nodeFeature in pairs(DB.getChildren(nodeActor, "featurelist")) do
				local sFeatureName = StringManager.trim(DB.getValue(nodeFeature, "name", ""):lower())
				if sFeatureName == "spellcasting" then
					local sDesc = DB.getValue(nodeFeature, "text", ""):lower();
					local sStat = sDesc:match("(%w+) is your spellcasting ability") or ""
					nSpellcastingDC = nSpellcastingDC + ActorManager5E.getAbilityBonus(rActor, sStat) 
					break
				end
			end 	
		elseif sNodeType == "ct" then
			nSpellcastingDC = 8 +  ActorManager5E.getAbilityBonus(rActor, "prf") + nDC
			for _,nodeTrait in pairs(DB.getChildren(nodeActor, "traits")) do
				local sTraitName = StringManager.trim(DB.getValue(nodeTrait, "name", ""):lower())
				if sTraitName == "spellcasting" then
					local sDesc = DB.getValue(nodeTrait, "desc", ""):lower();
					local sStat = sDesc:match("its spellcasting ability is (%w+)") or ""
					nSpellcastingDC = nSpellcastingDC + ActorManager5E.getAbilityBonus(rActor, sStat)
					break
				end
			end
		end
		rNewEffect.sName = rNewEffect.sName:gsub("%[SDC]", tostring(nSpellcastingDC))
		rNewEffect.sName = rNewEffect.sName:gsub("%(SDC%)", tostring(nSpellcastingDC))
	end
end


function onSaveRollHandler5E(rSource, rTarget, rRoll)
	local nodeEffect = DB.findNode(rRoll.sEffectPath)
	if not nodeEffect then
		return
	end
	local sName = ActorManager.getDisplayName(nodeSource)
	ActionSave.onSave(rTarget, rSource, rRoll) -- Reverse target/source because the target of the effect is making the save
	local nResult = ActionsManager.total(rRoll)
	local bAct = false
	if rRoll.bActonFail then
		if nResult < tonumber(rRoll.nTarget) then
			bAct = true
		end
	else
		if nResult >= tonumber(rRoll.nTarget) then
			bAct = true
		end
	end
	local sEffect = DB.getValue(nodeEffect, "label", "");
	if bAct then
		if rRoll.sDesc:match( " %[HALF ON SAVE%]") then
			EffectsManagerBCEDND.applyOngoingDamage(rSource, rTarget, nodeEffect, true, false);
		end
		if rRoll.bRemoveOnSave then
			EffectsManagerBCE.modifyEffect(nodeEffect, "Remove");
		elseif rRoll.bDisableOnSave then
			EffectsManagerBCE.modifyEffect(nodeEffect, "Deactivate");
		end
		if sEffect:match("SAVEADDP") then
			local rEffect = EffectsManagerBCE.matchEffect(sEffect, {"SAVEADDP"});
			if rEffect.sName ~= nil then
				local nodeTarget = ActorManager.getCTNode(rTarget);
				rEffect.sSource = ActorManager.getCTNodeName(rSource);
				rEffect.nInit  = DB.getValue(nodeTarget, "initresult", 0);
				EffectManager.addEffect("", "", nodeTarget, rEffect, true);
			end
		end
	else
		EffectsManagerBCEDND.applyOngoingDamage(rSource, rTarget, nodeEffect, false, false);
		if sEffect:match("SAVEADD") then
			local rEffect = EffectsManagerBCE.matchEffect(sEffect, {"SAVEADD"});
			if rEffect.sName ~= nil then
				local nodeTarget = ActorManager.getCTNode(rTarget);
				rEffect.sSource = ActorManager.getCTNodeName(rSource);
				rEffect.nInit  = DB.getValue(nodeTarget, "initresult", 0);
				EffectManager.addEffect("", "", nodeTarget, rEffect, true);
			end
		end
	end
end
function onDamage(rSource,rTarget, nodeEffect)
	if EffectsManagerBCE.processEffect(rTarget, nodeEffect,"SAVEONDMG", rSource) then
		local nodeTarget = ActorManager.getCTNode(rTarget)
		saveEffect(nodeEffect, nodeTarget, "Save")
	end
end
function saveEffect(nodeEffect, nodeTarget, sSaveBCE) -- Effect, Node which this effect is on, BCE String
	local sEffect = DB.getValue(nodeEffect, "label", "")
	if (DB.getValue(nodeEffect, "isactive", 0) ~= 1 ) then
		return
	end
	local aEffectComps = EffectManager.parseEffect(sEffect)
	local sLabel = ""
	for _,sEffectComp in ipairs(aEffectComps) do
		local rEffectComp = EffectManager.parseEffectCompSimple(sEffectComp)
		if rEffectComp.type == "SAVEE" or rEffectComp.type == "SAVES" or rEffectComp.type == "SAVEA" or rEffectComp.type == "SAVEONDMG" then
			local sAbility = rEffectComp.remainder[1]
			if User.getRulesetName() == "5E" then
				sAbility = DataCommon.ability_stol[sAbility]
			end
			local nDC = tonumber(rEffectComp.remainder[2])
			if  (nDC and sAbility) ~= nil then		
				local sNodeEffectSource  = DB.getValue(nodeEffect, "source_name", "")
				if sLabel == "" then
					sLabel = "Ongoing Effect"
				end
				local rSaveVsRoll = {}
				rSaveVsRoll.sType = "savebce"
				rSaveVsRoll.aDice = {}
				rSaveVsRoll.sSaveType = sSaveBCE
				rSaveVsRoll.nTarget = nDC -- Save DC
				rSaveVsRoll.sSource = sNodeEffectSource
				rSaveVsRoll.sDesc = "[SAVE VS] " .. sLabel
				if rSaveVsRoll then
					rSaveVsRoll.sDesc = rSaveVsRoll.sDesc .. " [" .. sAbility .. " DC " .. rSaveVsRoll.nTarget .. "]";
				end
				if rEffectComp.original:match("%(M%)") then
					rSaveVsRoll.sDesc = rSaveVsRoll.sDesc .. " [MAGIC]";
				end
				if rEffectComp.original:match("%(H%)") then
					rSaveVsRoll.sDesc = rSaveVsRoll.sDesc .. " [HALF ON SAVE]";
				end
				rSaveVsRoll.sSaveDesc = rSaveVsRoll.sDesc
				if EffectManager.isGMEffect(sourceNodeCT, nodeEffect) or CombatManager.isCTHidden(sourceNodeCT) then
					rSaveVsRoll.bSecret = true
				end
				if rEffectComp.original:match("%(D%)") then
					rSaveVsRoll.bDisableOnSave = true
				end
				if rEffectComp.original:match("%(R%)") then
					rSaveVsRoll.bRemoveOnSave = true
				end
				if rEffectComp.original:match("%(F%)") then
					rSaveVsRoll.bActonFail = true
				end

				rSaveVsRoll.sSaveDesc = rSaveVsRoll.sDesc .. "[TYPE " .. sEffect .. "]" 
				local rRoll = {}
				rRoll = ActionSave.getRoll(nodeTarget,sAbility) -- call to get the modifiers
				rSaveVsRoll.nMod = rRoll.nMod -- Modfiers 
				rSaveVsRoll.aDice = rRoll.aDice
				rSaveVsRoll.sEffectPath = nodeEffect.getPath()
				rSaveVsRoll.sApply = DB.getValue(nodeEffect, "apply", "");

				ActionsManager.actionRoll(sNodeEffectSource,{{nodeTarget}}, {rSaveVsRoll})
				break  
			end
		elseif rEffectComp.type == "" and sLabel == "" then
			sLabel = sEffectComp
		end
	end
end


function getReductionType(rSource, rTarget, sEffectType, rDamageOutput)
	local aEffects = EffectManager5E.getEffectsByType(rTarget, sEffectType, rDamageOutput.aDamageFilter, rSource);
	local aFinal = {};
	for _,v in pairs(aEffects) do
		local rReduction = {};
		
		rReduction.mod = v.mod;
		rReduction.aNegatives = {};
		for _,vType in pairs(v.remainder) do
			if #vType > 1 and ((vType:sub(1,1) == "!") or (vType:sub(1,1) == "~")) then
				if StringManager.contains(DataCommon.dmgtypes, vType:sub(2)) then
					table.insert(rReduction.aNegatives, vType:sub(2));
				end
			end
		end

		for _,vType in pairs(v.remainder) do
			if vType ~= "untyped" and vType ~= "" and vType:sub(1,1) ~= "!" and vType:sub(1,1) ~= "~" then
				if StringManager.contains(DataCommon.dmgtypes, vType) or vType == "all" then
					aFinal[vType] = rReduction;
				end
			end
		end
	end
	
	return aFinal;
end


function customGetDamageAdjust(rSource, rTarget, nDamage, rDamageOutput)
	local nDamageAdjust = 0
	local nReduce = 0
	local bVulnerable, bResist
	local aReduce = getReductionType(rSource, rTarget, "DMGR", rDamageOutput)

	for k, v in pairs(rDamageOutput.aDamageTypes) do
		-- Get individual damage types for each damage clause
		local aSrcDmgClauseTypes = {}
		local aTemp = StringManager.split(k, ",", true)
		for _,vType in ipairs(aTemp) do
			if vType ~= "untyped" and vType ~= "" then
				table.insert(aSrcDmgClauseTypes, vType)
			end
		end
		local nLocalReduce = ActionDamage.checkNumericalReductionType(aReduce, aSrcDmgClauseTypes, v)
		--We need to do this nonsense because we need to reduce damagee before resist calculation
		if nLocalReduce > 0 then
			rDamageOutput.aDamageTypes[k] = rDamageOutput.aDamageTypes[k] - nLocalReduce
			nDamage = nDamage - nLocalReduce
		end
		nReduce = nReduce + nLocalReduce
	end
	if (nReduce > 0) then
		table.insert(rDamageOutput.tNotifications, "[REDUCED]");
	end
	nDamageAdjust, bVulnerable, bResist = getDamageAdjust(rSource, rTarget, nDamage, rDamageOutput)
	nDamageAdjust = nDamageAdjust - nReduce
	return nDamageAdjust, bVulnerable, bResist 
end

--5E Only - Check if this effect has concentration and drop all previous effects of concentration from the source
function dropConcentration(rNewEffect, nDuration)
	if(rNewEffect.sName:match("%(C%)")) then
		local nodeCT = CombatManager.getActiveCT()
		local sSourceName = rNewEffect.sSource
		if sSourceName == "" then
			sSourceName = ActorManager.getCTPathFromActorNode(nodeCT)
		end
		local sSource
		local ctEntries = CombatManager.getSortedCombatantList()
		local aEffectComps = EffectManager.parseEffect(rNewEffect.sName)
		local sNewEffectTag = aEffectComps[1]
		for _, nodeCTConcentration in pairs(ctEntries) do
			if nodeCT == nodeCTConcentration then
				sSource = ""
			else
				sSource = sSourceName
			end
			for _,nodeEffect in pairs(DB.getChildren(nodeCTConcentration, "effects")) do
				local sEffect = DB.getValue(nodeEffect, "label", "")
				aEffectComps = EffectManager.parseEffect(sEffect)
				local sEffectTag = aEffectComps[1]
				if (sEffect:match("%(C%)") and (DB.getValue(nodeEffect, "source_name", "") == sSource)) and 
						(sEffectTag ~= sNewEffectTag) or
						((sEffectTag == sNewEffectTag and (DB.getValue(nodeEffect, "duration", 0) ~= nDuration))) then
							EffectsManagerBCE.modifyEffect(nodeEffect, "Remove", sEffect)
				end
			end
		end
	end
end

-- Needed for ongoing save. Have to flip source/target to get the correct mods
function onModSaveHandler(rSource, rTarget, rRoll)
	if bAutomaticSave == true then
		ActionSaveASA.customModSave(rTarget, rSource, rRoll)
	else
		ActionSave.modSave(rTarget, rSource, rRoll)
	end
end

function customParseEffects(sPowerName, aWords)
	if OptionsManager.isOption("AUTOPARSE_EFFECTS", "off") then
		return parseEffects(sPowerName, aWords)
	end
	local effects = {};
	local rCurrent = nil;
	local rPrevious = nil;
	local i = 1;
	local bStart = false
	local bSource = false
	while aWords[i] do
		if StringManager.isWord(aWords[i], "damage") then
			i, rCurrent = PowerManager.parseDamagePhrase(aWords, i);
			if rCurrent then
				if StringManager.isWord(aWords[i+1], "at") and 
						StringManager.isWord(aWords[i+2], "the") and
						StringManager.isWord(aWords[i+3], { "start", "end" }) and
						StringManager.isWord(aWords[i+4], "of") then
					if StringManager.isWord(aWords[i+3],  "start") then
						bStart = true
					end
					local nTrigger = i + 4;
					if StringManager.isWord(aWords[nTrigger+1], "each") and
							StringManager.isWord(aWords[nTrigger+2], "of") then
						if StringManager.isWord(aWords[nTrigger+3], "its") then 
							nTrigger = nTrigger + 3;
						else
							nTrigger = nTrigger + 4;
							bSource = true
						end
					elseif StringManager.isWord(aWords[nTrigger+1], "its") then
						nTrigger = i;
					elseif StringManager.isWord(aWords[nTrigger+1], "your") then
						nTrigger = nTrigger + 1;
					end
					if StringManager.isWord(aWords[nTrigger+1], { "turn", "turns" }) then
						nTrigger = nTrigger + 1;
					end
					rCurrent.endindex = nTrigger;
					
					if StringManager.isWord(aWords[rCurrent.startindex - 1], "takes") and
							StringManager.isWord(aWords[rCurrent.startindex - 2], "and") and
							StringManager.isWord(aWords[rCurrent.startindex - 3], DataCommon.conditions) then
						rCurrent.startindex = rCurrent.startindex - 2;
					end
					
					local aName = {};
					for _,v in ipairs(rCurrent.clauses) do
						local sDmg = StringManager.convertDiceToString(v.dice, v.modifier);
						if v.dmgtype and v.dmgtype ~= "" then
							sDmg = sDmg .. " " .. v.dmgtype;
						end
						if bStart == true and bSource == false then
							table.insert(aName, "DMGO: " .. sDmg)
						elseif bStart ==false and bSource == false then
							table.insert(aName, "DMGOE: " .. sDmg)
						elseif bStart == true and bSource == true then
							table.insert(aName, "SDMGOS: " .. sDmg)
						elseif bStart == false and bSource == true then
							table.insert(aName, "SDMGOE: " .. sDmg)
						end
					end
					rCurrent.clauses = nil;
					rCurrent.sName = table.concat(aName, "; ");
					rPrevious = rCurrent
				elseif StringManager.isWord(aWords[rCurrent.startindex - 1], "extra") then
					rCurrent.startindex = rCurrent.startindex - 1;
					rCurrent.sTargeting = "self";
					rCurrent.sApply = "roll";
					
					local aName = {};
					for _,v in ipairs(rCurrent.clauses) do
						local sDmg = StringManager.convertDiceToString(v.dice, v.modifier);
						if v.dmgtype and v.dmgtype ~= "" then
							sDmg = sDmg .. " " .. v.dmgtype;
						end
						table.insert(aName, "DMG: " .. sDmg);
					end
					rCurrent.clauses = nil;
					rCurrent.sName = table.concat(aName, "; ");
					rPrevious = rCurrent
				else
					rCurrent = nil;
				end
			end
		-- Handle ongoing saves 
		elseif  StringManager.isWord(aWords[i], "repeat") and StringManager.isWord(aWords[i+2], "saving") and 
			StringManager.isWord(aWords[i +3], "throw") then
				local tSaves = PowerManager.parseSaves(sPowerName, aWords, false, false)
				local aSave = tSaves[#tSaves]
				if aSave == nil then
					break
				end
				local j = i+3
				local bStartTurn = false
				local bEndSuccess = false
				local aName = {};
				local sClause = nil;
				
				while aWords[j] do
					if StringManager.isWord(aWords[j], "start") then
						bStartTurn = true
					end
					if StringManager.isWord(aWords[j], "ending") then
						bEndSuccess = true
					end
					j = j+1
				end
				if bStartTurn == true then
					sClause = "SAVES:"
				else
					sClause = "SAVEE:"
				end
				
				sClause  = sClause .. " " .. DataCommon.ability_ltos[aSave.save]
				sClause  = sClause .. " " .. aSave.savemod
				
				if bEndSuccess == true then
					sClause = sClause .. " (R)"
				end

				table.insert(aName, aSave.label);
				if rPrevious ~= nil then
					table.insert(aName, rPrevious.sName)
				end
				table.insert(aName, sClause);
				rCurrent = {}
				rCurrent.startindex = i
				rCurrent.endindex = i+3
				rCurrent.sName = table.concat(aName, "; ");
		elseif (i > 1) and StringManager.isWord(aWords[i], DataCommon.conditions) then
			local bValidCondition = false;
			local nConditionStart = i;
			local j = i - 1;
			local sTurnModifier = getTurnModifier(aWords, i)
			while aWords[j] do
				if StringManager.isWord(aWords[j], "be") then
					if StringManager.isWord(aWords[j-1], "or") then
						bValidCondition = true;
						nConditionStart = j;
						break;
					end
				
				elseif StringManager.isWord(aWords[j], "being") and
						StringManager.isWord(aWords[j-1], "against") then
					bValidCondition = true;
					nConditionStart = j;
					break;
				
				elseif StringManager.isWord(aWords[j], { "also", "magically" }) then
				
				-- Special handling: Blindness/Deafness
				elseif StringManager.isWord(aWords[j], "or") and StringManager.isWord(aWords[j-1], DataCommon.conditions) and 
						StringManager.isWord(aWords[j-2], "either") and StringManager.isWord(aWords[j-3], "is") then
					bValidCondition = true;
					break;
					
				elseif StringManager.isWord(aWords[j], { "while", "when", "cannot", "not", "if", "be", "or" }) then
					bValidCondition = false;
					break;
				
				elseif StringManager.isWord(aWords[j], { "target", "creature", "it" }) then
					if StringManager.isWord(aWords[j-1], "the") then
						j = j - 1;
					end
					nConditionStart = j;
					
				elseif StringManager.isWord(aWords[j], "and") then
					if #effects == 0 then
						break;
					elseif effects[#effects].endindex ~= j - 1 then
						if not StringManager.isWord(aWords[i], "unconscious") and not StringManager.isWord(aWords[j-1], "minutes") then
							break;
						end
					end
					bValidCondition = true;
					nConditionStart = j;
					
				elseif StringManager.isWord(aWords[j], "is") then
					if bValidCondition or StringManager.isWord(aWords[i], "prone") or
							(StringManager.isWord(aWords[i], "invisible") and StringManager.isWord(aWords[j-1], {"wearing", "wears", "carrying", "carries"})) then
						break;
					end
					bValidCondition = true;
					nConditionStart = j;
				
				elseif StringManager.isWord(aWords[j], DataCommon.conditions) then
					break;

				elseif StringManager.isWord(aWords[i], "poisoned") then
					if (StringManager.isWord(aWords[j], "instead") and StringManager.isWord(aWords[j-1], "is")) then
						bValidCondition = true;
						nConditionStart = j - 1;
						break;
					elseif StringManager.isWord(aWords[j], "become") then
						bValidCondition = true;
						nConditionStart = j;
						break;
					end
				
				elseif StringManager.isWord(aWords[j], {"knock", "knocks", "knocked", "fall", "falls"}) and StringManager.isWord(aWords[i], "prone")  then
					bValidCondition = true;
					nConditionStart = j;
					
				elseif StringManager.isWord(aWords[j], {"knock", "knocks", "fall", "falls", "falling", "remain", "is"}) and StringManager.isWord(aWords[i], "unconscious") then
					if StringManager.isWord(aWords[j], "falling") and StringManager.isWord(aWords[j-1], "of") and StringManager.isWord(aWords[j-2], "instead") then
						break;
					end
					if StringManager.isWord(aWords[j], "fall") and StringManager.isWord(aWords[j-1], "you") and StringManager.isWord(aWords[j-1], "if") then
						break;
					end
					if StringManager.isWord(aWords[j], "falls") and StringManager.isWord(aWords[j-1], "or") then
						break;
					end
					bValidCondition = true;
					nConditionStart = j;
					if StringManager.isWord(aWords[j], "fall") and StringManager.isWord(aWords[j-1], "or") then
						break;
					end
					
				elseif StringManager.isWord(aWords[j], {"become", "becomes"}) and StringManager.isWord(aWords[i], "frightened")  then
					bValidCondition = true;
					nConditionStart = j;
					break;
					
				elseif StringManager.isWord(aWords[j], {"turns", "become", "becomes"}) 
						and StringManager.isWord(aWords[i], {"invisible"}) then
					if StringManager.isWord(aWords[j-1], {"can't", "cannot"}) then
						break;
					end
					bValidCondition = true;
					nConditionStart = j;
				
				-- Special handling: Blindness/Deafness
				elseif StringManager.isWord(aWords[j], "either") and StringManager.isWord(aWords[j-1], "is") then
					bValidCondition = true;
					break;
				
				else
					break;
				end
				j = j - 1;
			end
			
			if bValidCondition then
				rCurrent = {};
				rCurrent.sName = sPowerName .. "; " .. StringManager.capitalize(aWords[i]);
				rCurrent.startindex = nConditionStart;
				rCurrent.endindex = i;
				if sRemoveTurn ~= "" then
					rCurrent.sName = rCurrent.sName .. "; " .. sTurnModifier
				end
				rPrevious = rCurrent
			end
		end
		
		if rCurrent then
			PowerManager.parseEffectsAdd(aWords, i, rCurrent, effects);
			rCurrent = nil;
		end
		
		i = i + 1;
	end

	if rCurrent then
		PowerManager.parseEffectsAdd(aWords, i - 1, rCurrent, effects);
	end
	
	-- Handle duration field in NPC spell translations
	i = 1;
	while aWords[i] do
		if StringManager.isWord(aWords[i], "duration") and StringManager.isWord(aWords[i+1], ":") then
			j = i + 2;
			local bConc = false;
			if StringManager.isWord(aWords[j], "concentration") and StringManager.isWord(aWords[j+1], "up") and StringManager.isWord(aWords[j+2], "to") then
				bConc = true;
				j = j + 3;
			end
			if StringManager.isNumberString(aWords[j]) and StringManager.isWord(aWords[j+1], {"round", "rounds", "minute", "minutes", "hour", "hours", "day", "days"}) then
				local nDuration = tonumber(aWords[j]) or 0;
				local sUnits = "";
				if StringManager.isWord(aWords[j+1], {"minute", "minutes"}) then
					sUnits = "minute";
				elseif StringManager.isWord(aWords[j+1], {"hour", "hours"}) then
					sUnits = "hour";
				elseif StringManager.isWord(aWords[j+1], {"day", "days"}) then
					sUnits = "day";
				end

				for _,vEffect in ipairs(effects) do
					if not vEffect.nDuration and (vEffect.sName ~= "Prone") then
						if bConc then
							vEffect.sName = vEffect.sName .. "; (C)";
						end
						vEffect.nDuration = nDuration;
						vEffect.sUnits = sUnits;
					end
				end

				-- Add direct effect right from concentration text
				if bConc then
					local rConcentrate = {};
					rConcentrate.sName = sPowerName .. "; (C)";
					rConcentrate.startindex = i;
					rConcentrate.endindex = j+1;

					PowerManager.parseEffectsAdd(aWords, i, rConcentrate, effects);
				end
			end
		end
		i = i + 1;
	end
	
	return effects;
end

function getTurnModifier(aWords, i)
	local sRemoveTurn = ""
	while aWords[i] do
		if StringManager.isWord(aWords[i], "until") and
			StringManager.isWord(aWords[i+1], "the") and
			StringManager.isWord(aWords[i+2], {"start","end"}) and 
			StringManager.isWord(aWords[i+3], "of") then 
			if StringManager.isWord(aWords[i+4], "its") then
				if StringManager.isWord(aWords[i+2], "start") then
					sRemoveTurn = "TURNRS"
				else
					sRemoveTurn = "TURNRE"
				end
			else
				if StringManager.isWord(aWords[i+2], "start") then
					sRemoveTurn = "STURNRS"
				else
					sRemoveTurn = "STURNRE"
				end
			end
		end
		i = i +1
	end
	return sRemoveTurn
end