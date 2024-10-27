--  	Author: Ryan Hagelstrom
--      Please see the license file included with this distribution for
--      attribution and copyright information.
--
-- luacheck: globals DiceManagerDnDBCE BCEManager
-- luacheck: globals onInit onClose moddedConvertStringToDice isDie
local convertStringToDice = nil;

function onInit()
    convertStringToDice = DiceManager.convertStringToDice;
    DiceManager.convertStringToDice = moddedConvertStringToDice;
end

function onClose()
    DiceManager.convertStringToDice = convertStringToDice;
end

function moddedConvertStringToDice(s)
    -- BCEManager.chat("moddedConvertStringToDice : ");
    local tDice = {};
    local nMod = 0;
    local tTerms = DiceManager.convertDiceStringToTerms(s);
    for _, vTerm in ipairs(tTerms) do
        if StringManager.isNumberString(vTerm) then
            nMod = nMod + (tonumber(vTerm) or 0);
        else
            local nDieCount, sDieType = DiceManager.parseDiceTerm(vTerm);
            if sDieType then
                local i = 1;
                while i <= nDieCount do
                    table.insert(tDice, sDieType);
                    i = i + 1;
                end
                -- next two lines enable "-X" ability replacement
            elseif vTerm and vTerm == '-X' then
                nMod = 0;
            end
        end
    end
    return tDice, nMod;
end

function isDie(rTarget, rEffect, sNodeEffect)
    BCEManager.chat('isDie : ', rEffect);

    local tEffectComps = EffectManager.parseEffect(rEffect.sName);
    for _, sEffectComp in ipairs(tEffectComps) do
        local aWords = StringManager.parseWords(sEffectComp, '%.%[%]%(%):');
        if #aWords > 0 then
            local sType = aWords[1]:match('^([^:]+):');
            -- Only roll dice for ability score mods
            if sType and
                (sType == 'STR' or sType == 'DEX' or sType == 'CON' or sType == 'INT' or sType == 'WIS' or sType == 'CHA') then
                local sValueCheck;
                local sTypeRemainder = aWords[1]:sub(#sType + 2);
                if sTypeRemainder == '' then
                    sValueCheck = aWords[2] or '';
                else
                    sValueCheck = sTypeRemainder;
                end
                -- Check to see if negative
                if sValueCheck:match('%-^[d%.%dF%+%-]+$') then
                    sValueCheck = sValueCheck:gsub('%-', '', 1);
                end
                if sValueCheck ~= '' and not StringManager.isNumberString(sValueCheck) and StringManager.isDiceString(sValueCheck) then
                    local rRoll = {};
                    local aDice, nMod = StringManager.convertStringToDice(sValueCheck);
                    rRoll.sType = 'effectbce';
                    rRoll.sDesc = '[EFFECT ' .. rEffect.sName .. '] ';
                    rRoll.aDice = aDice;
                    rRoll.sSubType = sType;
                    rRoll.nMod = nMod;
                    rRoll.sEffect = rEffect.sName;
                    rRoll.sValue = sValueCheck;
                    rRoll.rActor = rTarget;
                    rRoll.sNodeCT = sNodeEffect;
                    if rEffect.nGMOnly then
                        rRoll.bSecret = true;
                    else
                        rRoll.bSecret = false;
                    end
                    BCEManager.chat('Roll : ', rRoll);
                    ActionsManager.performAction(nil, rTarget, rRoll);
                end
            end
        end
    end
end
