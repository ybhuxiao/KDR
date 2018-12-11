--[[[
@module Heal/Raid Status
Helper functions for Raiders in Groups or Raids mainly aimed for healing rotations, but might be useful
for some DPS Rotations too.
]]--

local _raidStatus = {}
_raidStatus[1] = {}
_raidStatus[2] = {}
local raidStatus = _raidStatus[1]
local _raidStatusIdx = 1
local raidStatusSize = 0
local raidType = nil

local raidHealTargets = {}
local groupHealTargets = {}

local moduleLoaded = false
local function updateRaidStatus()
    if _raidStatusIdx == 1 then _raidStatusIdx = 2 else _raidStatusIdx = 1 end
    table.wipe(_raidStatus[_raidStatusIdx])
    local newRaidStatusSize = 0
    local healTargets = nil

    if IsInRaid() then
        healTargets = raidHealTargets
        newRaidStatusSize = GetNumGroupMembers()
        raidType = "raid"
    else
        healTargets = groupHealTargets
        newRaidStatusSize = GetNumSubgroupMembers() + 1
        raidType = "group"
    end
    for i=1,newRaidStatusSize do
        _raidStatus[_raidStatusIdx][healTargets[i].name] = healTargets[i]
    end
    raidStatus = _raidStatus[_raidStatusIdx]
    raidStatusSize = newRaidStatusSize
end

local function loadOnDemand()
    if not moduleLoaded then
        groupHealTargets[1] = kps.Unit.new("player")
        for i=2,5 do
            groupHealTargets[i] = kps.Unit.new("party"..(i-1))
            kps.env["party"..(i-1)] = groupHealTargets[i]
        end
        for i=1,40 do
            raidHealTargets[i] = kps.Unit.new("raid"..(i))
            kps.env["raid"..(i)] = raidHealTargets[i]
        end

        kps.events.registerOnUpdate(updateRaidStatus)
        moduleLoaded = true
    end
end


kps.RaidStatus = {}
kps.RaidStatus.prototype = {}
kps.RaidStatus.metatable = {}

function kps.RaidStatus.new(call_members)
    local inst = {}
    setmetatable(inst, kps.RaidStatus.metatable)
    inst.call_members = call_members
    return inst
end

kps.RaidStatus.metatable.__index = function (table, key)
    local fn = kps.RaidStatus.prototype[key]
    if fn == nil then
        error("Unknown Keys-Property '" .. key .. "'!")
    end
    loadOnDemand()
    if table.call_members then
        return fn(table)
    else
        return fn
    end
end


--[[[
@function `heal.count` - return the size of the current group
]]--
function kps.RaidStatus.prototype.count(self)
    return raidStatusSize
end

--[[[
@function `heal.type` - return the group type - either 'group' or 'raid'
]]--
function kps.RaidStatus.prototype.type(self)
    return raidType
end


local _tanksInRaid = {}
_tanksInRaid[1] = {}
_tanksInRaid[2] = {}
local _tanksInRaidIdx = 1

local tanksInRaid = kps.utils.cachedValue(function()
    if _tanksInRaidIdx == 1 then _tanksInRaidIdx = 2 else _tanksInRaidIdx = 1 end
    table.wipe(_tanksInRaid[_tanksInRaidIdx])
    for name,player in pairs(raidStatus) do
        if UnitGroupRolesAssigned(player.unit) == "TANK"
            or player.guid == kps["env"].focus.guid then
            table.insert(_tanksInRaid[_tanksInRaidIdx], player)
        end
    end
    return _tanksInRaid[_tanksInRaidIdx]
end)

-- Lowest Player in Raid
kps.RaidStatus.prototype.lowestInRaid = kps.utils.cachedValue(function()
    local lowestUnit = kps["env"].player
    local lowestHp = 2
    for name, unit in pairs(raidStatus) do
        if unit.isHealable and unit.hp < lowestHp then
            lowestUnit = unit
            lowestHp = lowestUnit.hp
        end
    end
    return lowestUnit
end)


-- Highest Player in Raid
kps.RaidStatus.prototype.highestInRaid = kps.utils.cachedValue(function()
    local highestUnit = kps["env"].player
    local highestHp = 0
    for name, unit in pairs(raidStatus) do
        if unit.isHealable and unit.hp > highestHp then
            highestUnit = unit
            highestHp = highestUnit.hp
        end
    end
    return highestUnit
end)

--[[[
@function `heal.lowestTankInRaid` - Returns the lowest tank in the raid - a tank is either:
    * any group member that has the Group Role `TANK`
    * is `focus` target
    * `player` if neither Group Role nor `focus` are set
]]--
kps.RaidStatus.prototype.lowestTankInRaid = kps.utils.cachedValue(function()
    local lowestUnit = kps["env"].player
    local lowestHp = 2
    for name,unit in pairs(tanksInRaid()) do
        if unit.isHealable and unit.hp < lowestHp then
            lowestUnit = unit
            lowestHp = lowestUnit.hp
        end
    end
    return lowestUnit
end)

--[[[
@function `heal.lowestUnitInRaid` - Returns the lowest unit in the raid - exclude tank
]]--

kps.RaidStatus.prototype.lowestUnitInRaid = kps.utils.cachedValue(function()
    local lowestUnit = kps["env"].player
    local lowestHp = 2
    for name,unit in pairs(raidStatus) do
        if unit.isHealable and not unit.isTankInRaid and unit.hp < lowestHp then
            lowestUnit = unit
            lowestHp = lowestUnit.hp
        end
    end
    return lowestUnit
end)

--[[[
@function `heal.defaultTarget` - Returns the default healing target based on these rules:
    * `player` if the player is below 20% hp incoming
    * `focus` if the focus is below 50% hp incoming (if the focus is not healable, `focustarget` is checked instead)
    * `target` if the target is below 50% hp incoming (if the target is not healable, `targettarget` is checked instead)
    * lowest tank in raid which is below 50% hp incoming
    * lowest raid member
    When used as a _target_ in your rotation, you *must* write `kps.heal.defaultTarget`!
]]--
kps.RaidStatus.prototype.defaultTarget = kps.utils.cachedValue(function()
    -- If we're below 30% - always heal us first!
    if kps.env.player.hp < 0.55 then return kps["env"].player end
    -- If the focus target is below 50% - take it (must be some reason there is a focus after all...)
    -- focus.isFriend coz isHealable (e.g. UnitInRange) is only available for members of the player's group.
    if kps["env"].focus.isFriend and kps["env"].focus.hp < 0.55 then return kps["env"].focus end
    -- MAYBE we also focused an enemy so we can heal it's target...
    if kps["env"].focustarget.isHealable and kps["env"].focustarget.hp < 0.55 then return kps["env"].focustarget end
    -- Now do the same for target...
    if kps["env"].target.isHealable and kps["env"].target.hp < 0.55 then return kps["env"].target end
    if not kps["env"].target.isHealable and kps["env"].targettarget.isHealable and kps["env"].targettarget.hp < 0.55 then return kps["env"].targettarget end
    -- Nothing selected - get lowest raid member
    return kps.RaidStatus.prototype.lowestInRaid()
end)

--[[[
@function `heal.defaultTank` - Returns the default tank based on these rules:
    * `player` if the player is below 20% hp incoming
    * `focus` if the focus is below 50% hp incoming (if the focus is not healable, `focustarget` is checked instead)
    * `target` if the target is below 50% hp incoming (if the target is not healable, `targettarget` is checked instead)
    * lowest tank in raid
    When used as a _target_ in your rotation, you *must* write `kps.heal.defaultTank`!
]]--
kps.RaidStatus.prototype.defaultTank = kps.utils.cachedValue(function()
    -- If we're below 30% - always heal us first!
    if kps.env.player.hp < 0.55 then return kps["env"].player end
    -- If the focus target is below 50% - take it (must be some reason there is a focus after all...) 
    -- focus.isFriend coz isHealable (e.g. UnitInRange) is only available for members of the player's group.
    if kps["env"].focus.isFriend and kps["env"].focus.hp < 0.55 then return kps["env"].focus end
    -- MAYBE we also focused an enemy so we can heal it's target...
    if kps["env"].focustarget.isHealable and kps["env"].focustarget.hp < 0.55 then return kps["env"].focustarget end
    -- Now do the same for target...
    if kps["env"].target.isHealable and kps["env"].target.hp < 0.55 then return kps["env"].target end
    if not kps["env"].target.isHealable and kps["env"].targettarget.isHealable and kps["env"].targettarget.hp < 0.55 then return kps["env"].targettarget end
    -- Nothing selected - get lowest Tank if it is NOT the player and lower than 50%
    return kps.RaidStatus.prototype.lowestTankInRaid()
end)

--[[[
@function `heal.averageHealthRaid` - Returns the average hp incoming for all raid members
]]--
kps.RaidStatus.prototype.averageHealthRaid = kps.utils.cachedValue(function()
    local hpIncTotal = 0
    local hpIncCount = 0
    for name, unit in pairs(raidStatus) do
        if unit.isHealable then
            hpIncTotal = hpIncTotal + unit.hp
            hpIncCount = hpIncCount + 1
        end
    end
    return hpIncTotal / hpIncCount
end)

--[[[
@function `heal.lossHealthRaid` - Returns the loss Health for all raid members
]]--
kps.RaidStatus.prototype.lossHealthRaid = kps.utils.cachedValue(function()
    local hpTotal = 0
    for name, unit in pairs(raidStatus) do
        if unit.isHealable then
            -- UnitHealthMax - UnitHealth
            local hpLoss = unit.hpMax - unit.hpTotal 
            hpTotal = hpTotal + hpLoss
        end
    end
    return hpTotal
end)

--[[[
@function `heal.incomingHealthRaid` - Returns the incoming Health for all raid members
]]--

kps.RaidStatus.prototype.incomingHealthRaid = kps.utils.cachedValue(function()
    local hpIncTotal = 0
    for name,player in pairs(raidStatus) do
        if player.isHealable then
            local hpInc = UnitGetIncomingHeals(player.unit)
            if not hpInc then hpInc = 0 end
            hpIncTotal = hpIncTotal + hpInc
        end
    end
    return hpIncTotal
end)

--[[[
@function `heal.countLossInRange(<PCT>)` - Returns the count for all raid members below threshold health e.g. heal.countLossInRange(0.90)
]]--

local countInRange = function(health)
    if health == nil then health = 2 end
    local count = 0
    for name, unit in pairs(raidStatus) do
        if unit.isHealable and unit.hp < health then
            count = count + 1
        end
    end
    return count
end

kps.RaidStatus.prototype.countLossInRange = kps.utils.cachedValue(function()
    return countInRange
end)

kps.RaidStatus.prototype.countInRange = kps.utils.cachedValue(function()
    local maxcount = 0
    for name, unit in pairs(raidStatus) do
        if unit.isHealable then
            maxcount = maxcount + 1
        end
    end
    return maxcount
end)

--[[[
@function `heal.countLossInDistance(<PCT>,<DIST>)` - Returns the count for all raid members below threshold health (default countInRange) in a distance (default 10 yards) e.g. heal.countLossInRange(0.90)
]]--

local countInDistance = function(health,distance)
    if distance == nil then distance = 10 end
    if health == nil then health = 2 end
    local count = 0
    for name, unit in pairs(raidStatus) do
        if unit.isHealable and unit.hp < health and unit.distance <= distance then
            count = count + 1
        end
    end
    return count
end

kps.RaidStatus.prototype.countLossInDistance = kps.utils.cachedValue(function()
    return countInDistance
end)

--[[[
@function `heal.aggroTankTarget` - Returns the tank with highest aggro on the current target (*not* the unit with the highest aggro!). If there is no tank in the target thread list, the `heal.defaultTank` is returned instead.
    When used as a _target_ in your rotation, you *must* write `kps.heal.aggroTankTarget`!
]]--

local function findAggroTankOfUnit(targetUnit)
    local allTanks = tanksInRaid()
    local highestThreat = 0
    local aggroTank = nil

    for name, possibleTank in pairs(allTanks) do
        local unitThreat = UnitThreatSituation(possibleTank.unit, targetUnit)
        if unitThreat and unitThreat > highestThreat then
            highestThreat = unitThreat
            aggroTank = possibleTank
        end
    end

    -- Nobody is tanking 'targetUnit' - return any tank...return 'defaultTank'
    if aggroTank == nil then
        return kps.RaidStatus.prototype.defaultTank()
    end
    return aggroTank
end

kps.RaidStatus.prototype.aggroTankTarget = kps.utils.cachedValue(function()
    return findAggroTankOfUnit("target")
end)

--[[[
@function `heal.aggroTankFocus` - Returns the tank with highest aggro on the current focus (*not* the unit with the highest aggro!). If there is no tank in the focus thread list, the `heal.defaultTank` is returned instead.
    When used as a _target_ in your rotation, you *must* write `kps.heal.aggroTankFocus`!
]]--

kps.RaidStatus.prototype.aggroTankFocus = kps.utils.cachedValue(function()
    return findAggroTankOfUnit("focus")
end)

--[[[
@function `heal.aggroTank` - Returns the tank or unit if overnuked with highest aggro and lowest health Without otherunit specified.
]]--
local tsort = table.sort
kps.RaidStatus.prototype.lowestAggroTank = kps.utils.cachedValue(function()
    local TankUnit = tanksInRaid()
    for name, player in pairs(raidStatus) do
        local unitThreat = UnitThreatSituation(player.unit)
        if unitThreat == 1 and player.isHealable then
            TankUnit[#TankUnit+1] = player
        elseif unitThreat == 3 and player.isHealable then
            TankUnit[#TankUnit+1] = player
        end
    end
    tsort(TankUnit, function(a,b) return a.hp < b.hp end)
    local myTank = TankUnit[1]
    if myTank == nil then myTank = kps["env"].player end
    return myTank
end)

--[[[
@function `heal.lowestTargetInRaid` - Returns the raid unit with lowest health targeted by enemy nameplate. nameplate must be enable.
]]--

kps.RaidStatus.prototype.lowestTargetInRaid = kps.utils.cachedValue(function()
    local lowestUnit = kps["env"].player
    local lowestHp = 2
    for name, unit in pairs(raidStatus) do
        if unit.isHealable and unit.isTarget and unit.hp < lowestHp then
            lowestUnit = unit
            lowestHp = lowestUnit.hp
        end
    end
    return lowestUnit
end)

--------------------------------------------------------------------------------------------
------------------------------- RAID DEBUFF
--------------------------------------------------------------------------------------------

--[[[
@function `heal.hasDebuffDispellable` - Returns the raid unit with dispellable debuff e.g. kps.heal.hasDebuffDispellable("Magic")
]]--

local dispelDebuffRaid = function (dispelType)
    local lowestUnit = false
    for name, player in pairs(raidStatus) do
        if player.isHealable and player.isDispellable(dispelType) then lowestUnit = player end
    end
    return lowestUnit
end

kps.RaidStatus.prototype.hasDebuffDispellable = kps.utils.cachedValue(function()
    return dispelDebuffRaid
end)

--[[[
@function `heal.isMagicDispellable` - Returns the raid unit with magic debuff to dispel e.g. {spells.purify, 'heal.isMagicDispellable' , kps.heal.isMagicDispellable },
]]--

kps.RaidStatus.prototype.isMagicDispellable = kps.utils.cachedValue(function()
    local lowestUnit = false
    for name, unit in pairs(raidStatus) do
        if unit.isHealable and unit.isDispellable("Magic") then lowestUnit = unit end
    end
    return lowestUnit
end)

--[[[
@function `heal.isDiseaseDispellable` - Returns the raid unit with disease debuff to dispel
]]--

kps.RaidStatus.prototype.isDiseaseDispellable = kps.utils.cachedValue(function()
    local lowestUnit = false
    for name, unit in pairs(raidStatus) do
        if unit.isHealable and unit.isDispellable("Disease") then lowestUnit = unit end
    end
    return lowestUnit
end)

--[[[
@function `heal.isPoisonDispellable` - Returns the raid unit with poison debuff to dispel
]]--

kps.RaidStatus.prototype.isPoisonDispellable = kps.utils.cachedValue(function()
    local lowestUnit = false
    for name, unit in pairs(raidStatus) do
        if unit.isHealable and unit.isDispellable("Poison") then lowestUnit = unit end
    end
    return lowestUnit
end)

--[[[
@function `heal.isCurseDispellable` - Returns the raid unit with curse debuff to dispel
]]--

kps.RaidStatus.prototype.isCurseDispellable = kps.utils.cachedValue(function()
    local lowestUnit = false
    for name, unit in pairs(raidStatus) do
        if unit.isHealable and unit.isDispellable("Curse") then lowestUnit = unit end
    end
    return lowestUnit
end)

--[[[
@function `heal.hasAbsorptionHeal` - Returns the raid unit with an absorption Debuff
]]--

kps.RaidStatus.prototype.hasAbsorptionHeal = kps.utils.cachedValue(function()
    local lowestUnit = false
    for name, unit in pairs(raidStatus) do
        if unit.isHealable and unit.absorptionHeal then lowestUnit = unit end
    end
    return lowestUnit
end)

--[[[
@function `heal.hasBossDebuff` - Returns the raid unit with a Boss Debuff
]]--

kps.RaidStatus.prototype.hasBossDebuff = kps.utils.cachedValue(function()
    local lowestUnit = false
    for name, unit in pairs(raidStatus) do
        if unit.isHealable and unit.hasBossDebuff then lowestUnit = unit end
    end
    return lowestUnit
end)

--[[[
@function `heal.hasBuffStacks(<BUFF>)` - Returns the buff stacks for a specific Buff on raid e.g. heal.hasBuffStacks(spells.prayerOfMending) < 10
]]--

local unitBuffStacks = function(spell)
    local charge = 0
    for name, unit in pairs(raidStatus) do
        if unit.isHealable and unit.hasBuff(spell) then
            local stacks = unit.buffStacks(spell)
            charge = charge + stacks
        end
    end
    return charge
end

kps.RaidStatus.prototype.hasBuffStacks = kps.utils.cachedValue(function()
    return unitBuffStacks
end)

--[[[
@function `heal.hasBuffCount(<BUFF>)` - Returns the buff count for a specific Buff on raid e.g. heal.hasBuffCount(spells.atonement) > 3
]]--

local unitBuffCount = function(spell)
    local count = 0
    for name, unit in pairs(raidStatus) do
        if unit.isHealable and unit.hasBuff(spell) then
            count = count + 1
        end
    end
    return count
end

kps.RaidStatus.prototype.hasBuffCount = kps.utils.cachedValue(function()
    return unitBuffCount
end)

--[[[
@function `heal.hasBuffAtonement` - Returns the UNIT with lowest health with Atonement Buff on raid e.g. heal.hasBuffAtonement.hp < 0.90
]]--

local unitHasBuff = function(spell)
    local lowestHp = 2
    local lowestUnit = kps["env"].player
    for name, unit in pairs(raidStatus) do
        if unit.isHealable and unit.myBuffDuration(spell) > 1 and unit.hp < lowestHp then
            lowestHp = unit.hp
            lowestUnit = unit
        end
    end
    return lowestUnit
end

kps.RaidStatus.prototype.hasBuffAtonement = kps.utils.cachedValue(function()
    return unitHasBuff(kps.spells.priest.atonement)
end)

--[[[
@function `heal.hasNotBuffAtonement` - Returns the UNIT with lowest health without Atonement Buff on raid e.g. heal.hasNotBuffAtonement.hp < 0.90
]]--

local unitHasNotBuff = function(spell)
    local lowestHp = 2
    local lowestUnit = kps["env"].player
    for name, unit in pairs(raidStatus) do
        if unit.isHealable and unit.myBuffDuration(spell) < 1 and unit.hp < lowestHp then
            lowestHp = unit.hp
            lowestUnit = unit
        end
    end
    return lowestUnit
end

kps.RaidStatus.prototype.hasNotBuffAtonement = kps.utils.cachedValue(function()
    return unitHasNotBuff(kps.spells.priest.atonement)
end)

--[[[
@function `heal.hasNotBuffMending` - Returns the lowest health unit without Prayer of Mending Buff on raid e.g. heal.hasNotBuffMending.hp < 0.90
]]--

kps.RaidStatus.prototype.hasNotBuffMending = kps.utils.cachedValue(function()
    return unitHasNotBuff(kps.spells.priest.prayerOfMending)
end)


--[[[
@function `heal.hasNotBuffRenew` - Returns the lowest health unit without Renew Buff on raid e.g. heal.hasNotBuffRenew.hp < 0.90
]]--

kps.RaidStatus.prototype.hasNotBuffRenew = kps.utils.cachedValue(function()
    return unitHasNotBuff(kps.spells.priest.renew)
end)

--[[[
@function `heal.hasBuffAtonementCount` - e.g. heal.hasBuffAtonementCount(0.85) > 3
]]--

local unitHasBuffHealth = function(health)
    local maxcount = 0
    local spell = kps.spells.priest.atonement -- kps.Spell.fromId(81749)
    for name, unit in pairs(raidStatus) do
        if unit.isHealable and unit.myBuffDuration(spell) > 1 and unit.hp < health then
            maxcount = maxcount + 1
        end
    end
    return maxcount
end

kps.RaidStatus.prototype.hasBuffAtonementCount = kps.utils.cachedValue(function()
    return unitHasBuffHealth
end)

--[[[
@function `heal.hasNotBuffAtonementCount` - e.g. heal.hasNotBuffAtonementCount(0.85) > 3
]]--

local unitHasNotBuffHealth = function(health)
    local maxcount = 0
    local spell = kps.spells.priest.atonement -- kps.Spell.fromId(81749)
    for name, unit in pairs(raidStatus) do
        if unit.isHealable and unit.myBuffDuration(spell) < 1 and unit.hp < health then
            maxcount = maxcount + 1
        end
    end
    return maxcount
end

kps.RaidStatus.prototype.hasNotBuffAtonementCount = kps.utils.cachedValue(function()
    return unitHasNotBuffHealth
end)

--[[[
@function `heal.atonementHealthRaid` - Returns the loss Health for all raid members with buff atonement
]]--
kps.RaidStatus.prototype.atonementHealthRaid = kps.utils.cachedValue(function()
    local hpTotal = 0
    local spell = kps.spells.priest.atonement -- kps.Spell.fromId(81749)
    for name, unit in pairs(raidStatus) do
        if unit.isHealable and unit.myBuffDuration(spell) > 1 then
            local hpLoss = unit.hpMax - unit.hpTotal
            hpTotal = hpTotal + hpLoss
        end
    end
    return hpTotal
end)

--[[[
@function `heal.hasNotBuffImportantUnit` - Returns the immportant unit (TANK,HEALER) with out a buff or false. heal.hasNotBuffAtonementImportantUnit(spells.atonement)
]]--

local importantUnitHasNotBuff = function (spell)
    for name,player in pairs(raidStatus) do
        if player.isHealable and player.myBuffDuration(spell) < 1 then
            if UnitGroupRolesAssigned(player.unit) == "TANK" or player.guid == kps["env"].focus.guid then
                return player
            elseif player.guid == kps["env"].player.guid and player.hp < 1 then
                return player  
            elseif UnitGroupRolesAssigned(player.unit) == "HEALER" and player.hp < 0.85 then
                return player
            end
        end
    end
    return false
end

local importantUnitHasNotBuffCount = function (spell)
    local count = 0
    for name,player in pairs(raidStatus) do
        if player.isHealable and player.myBuffDuration(spell) < 1 then
            if UnitGroupRolesAssigned(player.unit) == "TANK" or player.guid == kps["env"].focus.guid then
                count = count + 1
            elseif player.guid == kps["env"].player.guid and player.hp < 1 then
                count = count + 1  
            elseif UnitGroupRolesAssigned(player.unit) == "HEALER" and player.hp < 0.85 then
                count = count + 1
            end
        end
    end
    return count
end

kps.RaidStatus.prototype.hasNotBuffAtonementImportantUnit = kps.utils.cachedValue(function()
    return importantUnitHasNotBuff(kps.spells.priest.atonement)
end)

kps.RaidStatus.prototype.hasNotBuffAtonementImportantUnitCount = kps.utils.cachedValue(function()
    return importantUnitHasNotBuffCount(kps.spells.priest.atonement)
end)

--[[[
@function `heal.enemyTarget` - Returns the enemy target for all raid members
]]--
kps.RaidStatus.prototype.enemyTarget = kps.utils.cachedValue(function()
    local lowestUnit = "target"
    for name, player in pairs(raidStatus) do
        if player.isHealable and player.hasAttackableTarget then
            local friendUnit = player.unit
            local enemyTarget = friendUnit.."target"
            lowestUnit = enemyTarget
        end
    end
    return lowestUnit
end)

--[[[
@function `heal.enemyLowest` - Returns the lowest Health enemy target for all raid members
]]--
kps.RaidStatus.prototype.enemyLowest = kps.utils.cachedValue(function()
    local lowestUnit = "target"
    local lowestHp = 2
    for name, player in pairs(raidStatus) do
        if player.isHealable and player.hasAttackableTarget then
            local friendUnit = player.unit
            local enemyTarget = friendUnit.."target"
            local enemyHealth = UnitHealth(enemyTarget)
            if enemyHealth < lowestHp then
                lowestUnit = enemyTarget
                lowestHp = enemyHealth
            end
        end
    end
    return lowestUnit
end)


--------------------------------------------------------------------------------------------
------------------------------- TRICKY
--------------------------------------------------------------------------------------------

-- Here comes the tricky part - use an instance of RaidStatus which calls it's members
-- for 'kps.env.heal' - so we can write 'heal.defaultTarget.hp < xxx' in our rotations
kps.env.heal = kps.RaidStatus.new(true)
-- And use another instance of RaidStatus which returns the functions so we can write
-- kps.heal.defaultTarget as a target for our rotation tables.
kps.heal = kps.RaidStatus.new(false)

--------------------------------------------------------------------------------------------
------------------------------- TEST
--------------------------------------------------------------------------------------------

function kpstest()

--for name, player in pairs(raidStatus) do
--print("|cffffffffName: ",name,"Unit: ",player.unit,"Guid: ",player.guid)
--print("|cffff8000isHealable: ",player.isHealable,"|hp: ",player.hp,"|hpInc: ",player.hpIncoming)
--print("|cff1eff00HEAL: ",player.incomingHeal)
--print("|cFFFF0000DMG: ",player.incomingDamage)
--end

print("|cff1eff00LOWEST|cffffffff", kps["env"].heal.lowestInRaid.name,"/",kps["env"].heal.lowestInRaid.hp)
print("|cffff8000TARGET:|cffffffff", kps["env"].heal.lowestTargetInRaid.name,"/",kps["env"].heal.lowestTargetInRaid.hp)
print("|cffff8000TANK:|cffffffff", kps["env"].heal.lowestTankInRaid.name,"/",kps["env"].heal.lowestTankInRaid.hp)
print("|cffff8000LOWESTUNIT:|cffffffff", kps["env"].heal.lowestUnitInRaid.name,"/",kps["env"].heal.lowestUnitInRaid.hp)
--print("|cffff8000CountLossDistance_85:|cffffffff", kps["env"].heal.countLossInDistance(0.85,10))
print("|cffff8000CountLoss_90:|cffffffff", kps["env"].heal.countLossInRange(0.90),"|cffff8000countInRange:|cffffffff",kps["env"].heal.countInRange)

print("|cff1eff00HEAL:|cffffffff", kps["env"].heal.lowestTankInRaid.incomingHeal)
print("|cFFFF0000DMG:|cffffffff", kps["env"].heal.lowestTankInRaid.incomingDamage)

print("|cffff8000plateCount:|cffffffff", kps["env"].player.plateCount)
--print("|cffff8000plateCountvampiricTouch:|cffffffff", kps["env"].player.plateCountDebuff(kps.spells.priest.vampiricTouch))
--print("|cffff8000plateCountshadowWordPain:|cffffffff", kps["env"].player.plateCountDebuff(kps.spells.priest.shadowWordPain))
--local plateTable = kps["env"].player.plateTable
--for unitID,name in pairs(plateTable) do
--    print("unitID",unitID,"name",name)
--end

--local voidform = kps.spells.priest.voidform
--print("Count:",kps["env"].player.buffCount(voidform))
--print("Stacks:",kps["env"].player.buffStacks(voidform))

--print("|cffff8000averageHeal:|cffffffff", kps["env"].heal.averageHealthRaid)
--print("|cffff8000incomingHeal:|cffffffff", kps["env"].heal.incomingHealthRaid)
--print("|cffff8000lossHealth:|cffffffff", kps["env"].heal.lossHealthRaid)
--print("|cffff8000atonementHealth:|cffffffff", kps["env"].heal.atonementHealthRaid)

--print("|cffff8000Icicles:|cffffffff", kps["env"].player.buffStacks(kps.spells.mage.icicles))
--print("|cffff8000isUsable:|cffffffff", kps.spells.mage.glacialSpike.isUsable)

--local atonement = kps.spells.priest.atonement 
--print("|cffff8000BuffCount:|cffffffff", kps["env"].heal.hasBuffCount(atonement))
--print("|cffff8000BuffAtonementCount_90:|cffffffff", kps["env"].heal.hasBuffAtonementCount(0.90))
--print("|cffff8000NotBuffAtonementCount_90:|cffffffff", kps["env"].heal.hasNotBuffAtonementCount(0.90))
--
--print("|cffff8000ImportantUnit:|cffffffff", kps["env"].heal.hasNotBuffAtonementImportantUnit)
--print("|cffff8000hasNotBuffAtonementUnit:|cffffffff", kps["env"].heal.hasNotBuffAtonement.unit)

--local aura = kps.spells.priest.powerWordShield-- kps.spells.paladin.consecration
--print("myBuffDuration:",kps["env"].player.myBuffDuration(aura))
--print("hasBuff:",kps["env"].player.hasBuff(aura))

--local spell = kps.Spell.fromId(6572)
--local spellname = spell.name -- tostring(kps.spells.warrior.revenge)
--local spelltable = GetSpellPowerCost(spellname)[1] 
--for i,j in pairs(spelltable) do
--print(i," - ",j)
--end

--print("|cffff8000isStealable:|cffffffff", kps["env"].target.isStealable)
--print("|cffff8000isBuffDispellable:|cffffffff", kps["env"].target.isBuffDispellable)
--print("|cffff8000isDispellable:|cffffffff", kps["env"].player.isDispellable("Magic"))
--print("|cffff8000hasBossDebuff:|cffffffff", kps["env"].player.hasBossDebuff)

--local Atonement = kps.spells.priest.atonement -- kps.Spell.fromId(81749)
--print("|cffff8000AtonementCount:|cffffffff",kps["env"].heal.hasBuffAtonementCount(2))
--print("|cffff8000NotAtonementCount:|cffffffff",kps["env"].heal.hasNotBuffAtonementCount(2))
--print("|cffff8000AtonementUnit:|cffffffff", kps["env"].heal.hasBuffAtonement.name)
--print("|cffff8000NotAtonementUnit:|cffffffff", kps["env"].heal.hasNotBuffAtonement.name)


--for _,unit in ipairs(tanksInRaid()) do
--print("TANKS",unit.name)
--end
--
--for _,unit in ipairs(damageInRaid()) do
--print("DAMAGE",unit.name)
--end


--print("|cffff8000buffValue:|cffffffff", kps["env"].player.buffValue(kps.spells.warrior.ignorePain))
--print("|cffff8000countCharge:|cffffffff", kps.spells.priest.powerWordRadiance.charges)
--print("|cffff8000cooldownCharge:|cffffffff", kps.spells.priest.powerWordRadiance.cooldownCharges)
--print("|cffff8000cooldownSpellCharge:|cffffffff", kps.spells.priest.powerWordRadiance.cooldown)


--print("|cffff8000hasRoleInRaidTANK:|cffffffff", kps["env"].heal.lowestInRaid.hasRoleInRaid("TANK"))
--print("|cffff8000hasRoleInRaidHEALER:|cffffffff", kps["env"].heal.lowestInRaid.hasRoleInRaid("HEALER"))
--print("|cffff8000isTankInRaid:|cffffffff", kps["env"].heal.lowestInRaid.isTankInRaid)


--print("|cffff8000BuffValue:|cffffffff", kps["env"].player.buffDuration(kps.spells.priest.masteryEchoOfLight))
--print("|cffff8000BuffValue:|cffffffff", kps["env"].player.buffValue(kps.spells.priest.masteryEchoOfLight))

--print("|cffff8000TRINKET_0:|cffffffff", kps["env"].player.useTrinket(0))
--print("|cffff8000TRINKET_1:|cffffffff", kps["env"].player.useTrinket(1))

end

--[[
|cffe5cc80 = beige (artifact)
|cffff8000 = orange (legendary)
|cffa335ee = purple (epic)
|cff0070dd = blue (rare)
|cff1eff00 = green (uncommon)
|cffffffff = white (normal)
|cff9d9d9d = gray (crappy)
|cFFFFff00 = yellow
|cFFFF0000 = red
]]