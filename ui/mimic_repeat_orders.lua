local ffi = require("ffi")
local C = ffi.C

ffi.cdef [[
  typedef uint64_t UniverseID;

  typedef struct {
   size_t queueidx;
   const char* state;
   const char* statename;
   const char* orderdef;
   size_t actualparams;
   bool enabled;
   bool isinfinite;
   bool issyncpointreached;
   bool istemporder;
  } Order;

  typedef struct {
   const char* name;
   const char* transport;
   uint32_t spaceused;
   uint32_t capacity;
  } StorageInfo;

	typedef struct {
		const char* id;
		const char* name;
		const char* icon;
		const char* description;
		const char* category;
		const char* categoryname;
		bool infinite;
		uint32_t requiredSkill;
	} OrderDefinition;


	UniverseID GetPlayerID(void);

	bool GetOrderDefinition(OrderDefinition* result, const char* orderdef);
	const char* GetObjectIDCode(UniverseID objectid);
	bool IsComponentClass(UniverseID componentid, const char* classname);
	bool IsComponentOperational(UniverseID componentid);
	bool IsComponentWrecked(UniverseID componentid);
	uint32_t GetNumCargoTransportTypes(UniverseID containerid, bool merge);
	uint32_t GetCargoTransportTypes(StorageInfo* result, uint32_t resultlen, UniverseID containerid, bool merge, bool aftertradeorders);
	size_t GetOrderQueueFirstLoopIdx(UniverseID controllableid, bool* isvalid);
  uint32_t GetOrders(Order* result, uint32_t resultlen, UniverseID controllableid);
	uint32_t CreateOrder(UniverseID controllableid, const char* orderid, bool default);
	bool EnablePlannedDefaultOrder(UniverseID controllableid, bool checkonly);
	bool SetOrderLoop(UniverseID controllableid, size_t orderidx, bool checkonly);
  void ResetOrderLoop(UniverseID controllableid);
	bool EnableOrder(UniverseID controllableid, size_t idx);


	bool RemoveCommander2(UniverseID controllableid);
	uint32_t GetNumAllCommanders(UniverseID controllableid, FleetUnitID fleetunitid);
	const char* GetSubordinateGroupAssignment(UniverseID controllableid, int group);

]]

local MimicRepeatOrders = {
  args = {},
  queueArgs = {},
  playerId = 0,
  mapMenu = {},
  sourceId = 0,
  loopOrdersSkillLimit = 0,
  targetIds = {},
  repeatOrdersCommanders = {},
}


local Lib = require("extensions.sn_mod_support_apis.ui.Library")

local debugTraceLevel = "none"

local function debugLog(fmt, ...)
  if type(DebugError) == "function" and debugTraceLevel ~= "none" then
    if select("#", ...) > 0 then
      DebugError("MimicRepeatOrders: " .. string.format(fmt, ...))
    else
      DebugError("MimicRepeatOrders: " .. fmt)
    end
  end
end

local function traceLog(fmt, ...)
  if type(DebugError) == "function" and debugTraceLevel == "trace" then
    if select("#", ...) > 0 then
      DebugError("MimicRepeatOrders: " .. string.format(fmt, ...))
    else
      DebugError("MimicRepeatOrders: " .. fmt)
    end
  end
end

function MimicRepeatOrders.onDebugLevelChanged()
  local cfg = GetNPCBlackboard(MimicRepeatOrders.playerId, "$MimicRepeatOrdersConfig")
  if cfg and cfg.debugLevel then
    debugTraceLevel = tostring(cfg.debugLevel)
    debugLog("Debug level changed to %s", debugTraceLevel)
  end
end

local function getPlayerId()
  local current = C.GetPlayerID()
  if current == nil or current == 0 then
    return
  end

  local converted = ConvertStringTo64Bit(tostring(current))
  if converted ~= 0 and converted ~= MimicRepeatOrders.playerId then
    debugLog("updating player_id to %s", converted)
    MimicRepeatOrders.playerId = converted
  end
end

local function toUniverseId(value)
  if value == nil then
    return 0
  end

  if type(value) == "number" then
    return value
  end

  local idStr = tostring(value)
  if idStr == "" or idStr == "0" then
    return 0
  end

  return ConvertStringTo64Bit(idStr)
end


local function getShipName(shipId)
  if shipId == 0 then
    return "Unknown"
  end
  local name = GetComponentData(ConvertStringToLuaID(tostring(shipId)), "name")
  local idCode = ffi.string(C.GetObjectIDCode(shipId))
  return string.format("%s (%s)", name, idCode)
end

function MimicRepeatOrders.recordResult()
  local data = MimicRepeatOrders.args or {}
  debugLog("recordResult called for command %s with result %s", data and data.command, data and data.result)
  if MimicRepeatOrders.playerId ~= 0 then
    local payload = data or {}
    SetNPCBlackboard(MimicRepeatOrders.playerId, "$MimicRepeatOrdersResponse", payload)
    AddUITriggeredEvent("MimicRepeatOrders", "Response")
  end
end

function MimicRepeatOrders.reportError(extraInfo)
  local data = MimicRepeatOrders.args or {}
  data.result = "error"
  if extraInfo == nil then
    extraInfo = {}
  end
  for k, v in pairs(extraInfo) do
    data[k] = v
  end
  MimicRepeatOrders.recordResult()

  local message = "MimicRepeatOrders error"
  if data.info then
    message = message .. ": " .. tostring(data.info)
  end
  if data.detail then
    message = message .. " (" .. tostring(data.detail) .. ")"
  end

  DebugError(message)
end

function MimicRepeatOrders.reportSuccess(extraStatus)
  local data = MimicRepeatOrders.args or {}
  data.result = extraStatus or "success"
  MimicRepeatOrders.recordResult()
end

function MimicRepeatOrders.isLoopEnabled(shipId)
  local shipId = toUniverseId(shipId)
  local hasLoop = ffi.new("bool[1]", false)
  local firstLoop = tonumber(C.GetOrderQueueFirstLoopIdx(shipId, hasLoop))
  return hasLoop[0]
end

function MimicRepeatOrders.getRepeatOrders(shipId)
  local shipId = toUniverseId(shipId)
  local numOrders = tonumber(C.GetNumOrders(shipId)) or 0
  local buf = ffi.new("Order[?]", numOrders)
  local count = C.GetOrders(buf, numOrders, shipId)
  local orders = {}
  for i = 0, numOrders - 1 do
    local orderData = buf[i]
    if (tonumber(orderData.queueidx) > 0 and ffi.string(orderData.orderdef) ~= "" and orderData.enabled and not orderData.istemporder) then
      local order = {
        idx = tonumber(orderData.queueidx),
        order = ffi.string(orderData.orderdef),
      }
      orders[#orders + 1] = order
    end
  end
  return orders
end

function MimicRepeatOrders.checkShip(shipId, transportTypes)
  local shipId = toUniverseId(shipId)
  if shipId == 0 then
    return false, { info = "InvalidShipID" }
  end
  local isShip = C.IsComponentClass(shipId, "ship")
  if not isShip then
    return false, { info = "NotAShip" }
  end
  local owner = GetComponentData(shipId, "owner")
  if owner ~= "player" then
    return false, { info = "NotPlayerShip", detail = "owner=" .. tostring(owner) }
  end
  if not C.IsComponentOperational(shipId) or C.IsComponentWrecked(shipId) then
    return false, { info = "ShipNotOperational" }
  end
  if (transportTypes ~= nil and type(transportTypes) == "table" and #transportTypes > 0) then
    for i = 1, #transportTypes do
      local transportType = transportTypes[i]
      if MimicRepeatOrders.getCargoCapacity(shipId, transportType) == 0 then
        return false, { info = "NoCargoCapacity" }
      end
    end
  end
  return true
end

function MimicRepeatOrders.getCargoCapacity(shipId, transportType)
  local menu = MimicRepeatOrders.mapMenu
  local shipId = toUniverseId(shipId)
  local numStorages = C.GetNumCargoTransportTypes(shipId, true)
  local buf = ffi.new("StorageInfo[?]", numStorages)
  local count = C.GetCargoTransportTypes(buf, numStorages, shipId, true, false)
  local capacity = 0
  for i = 0, count - 1 do
    local tags = menu.getTransportTagsFromString(ffi.string(buf[i].transport))
    if tags[transportType] == true then
      capacity = capacity + buf[i].capacity
    end
  end
  return capacity
end

function MimicRepeatOrders.ValidateSourceShip()
  local sourceId = MimicRepeatOrders.sourceId
  if MimicRepeatOrders.args ~= nil and MimicRepeatOrders.args.source ~= nil then
    sourceId = toUniverseId(MimicRepeatOrders.args.source)
  end
  local valid, errorData = MimicRepeatOrders.checkShip(sourceId)
  if not valid then
    return false, errorData
  end
  if MimicRepeatOrders.isLoopEnabled(sourceId) == false then
    return false, { info = "LoopNotEnabled" }
  end
  local orders = MimicRepeatOrders.getRepeatOrders(sourceId)
  if #orders == 0 then
    return false, { info = "NoRepeatOrders" }
  end
  debugLog("Source ship %s has %s repeat orders", getShipName(sourceId), #orders)
  return true
end

function MimicRepeatOrders.isValidTargetShip(target, transportTypes)
  local targetId = toUniverseId(target)
  local valid, errorData = MimicRepeatOrders.checkShip(targetId, transportTypes)
  if not valid then
    return false, errorData
  end
  local loopSkill = MimicRepeatOrders.loopOrdersSkillLimit;
  local aiPilot = GetComponentData(ConvertStringToLuaID(tostring(targetId)), "assignedaipilot")
  local aiPilotSkill = aiPilot and math.floor(C.GetEntityCombinedSkill(ConvertIDTo64Bit(aiPilot), nil, "aipilot") * 15 / 100) or -1
  traceLog("Target ship %s has AI pilot skill %s, required is %s", getShipName(targetId), aiPilotSkill, loopSkill)
  if aiPilotSkill < loopSkill then
    return false, { info = "TargetPilotSkillTooLow", detail = "skill=" .. tostring(aiPilotSkill) .. ", required=" .. tostring(loopSkill) }
  end
  return true
end

function MimicRepeatOrders.removeCommander(shipId)
  C.RemoveCommander2(shipId)
  C.CreateOrder(shipId, "Wait", true)
  C.EnablePlannedDefaultOrder(shipId, false)
end

function MimicRepeatOrders.getArgs()
  MimicRepeatOrders.args = {}
  if MimicRepeatOrders.playerId == 0 then
    debugLog("getArgs unable to resolve player id")
  else
    local list = GetNPCBlackboard(MimicRepeatOrders.playerId, "$MimicRepeatOrdersRequest")
    if type(list) == "table" and #list > 0 then
      debugLog("getArgs retrieved %s entries from blackboard", #list)
      for i = 1, #list do
        traceLog(" getArgs entry %s: %s", i, list[i])
        MimicRepeatOrders.queueArgs[#MimicRepeatOrders.queueArgs + 1] = list[i]
      end
      SetNPCBlackboard(MimicRepeatOrders.playerId, "$MimicRepeatOrdersRequest", nil)
    elseif list ~= nil then
      debugLog("getArgs received non-table payload of type %s", type(list))
    else
      debugLog("getArgs found no blackboard entries for player %s", MimicRepeatOrders.playerId)
    end
  end
  if #MimicRepeatOrders.queueArgs > 0 then
    MimicRepeatOrders.args = MimicRepeatOrders.queueArgs[1]
    table.remove(MimicRepeatOrders.queueArgs, 1)
    debugLog("getArgs processing command %s with %s remaining in queue",
      MimicRepeatOrders.args and MimicRepeatOrders.args.command, #MimicRepeatOrders.queueArgs)
    return true
  end
  return false
end

-- Generic order-param helpers -- driven entirely by GetOrderParams' own type metadata
-- (type/value/inputparams), so any order id the AI/engine reports is clonable without
-- per-order or per-param bookkeeping here.

local function findWareTransportType(orderParams)
  for i = 1, #orderParams do
    local p = orderParams[i]
    if p.type == "ware" and p.value ~= nil then
      return GetWareData(p.value, "transport")
    end
  end
  return nil
end

local function positionsEqual(sourceValue, targetValue)
  if tostring(sourceValue[1]) ~= tostring(targetValue[1]) then
    return false
  end
  local sourceOffset, targetOffset = sourceValue[2], targetValue[2]
  for _, axis in ipairs({ "x", "y", "z" }) do
    if math.abs(sourceOffset[axis] - targetOffset[axis]) > 0.01 then
      return false
    end
  end
  return true
end

-- true when this numeric param's own bound matches the ship's cargo capacity for the
-- order's ware -- i.e. it's a cargo-amount param (maxamount/minamount-style), not an
-- order-fixed bound like radius.
local function isCargoBoundParam(paramData, sourceCapacity)
  return paramData.type == "number" and sourceCapacity ~= nil
      and paramData.inputparams ~= nil and paramData.inputparams.max ~= nil
      and math.abs(paramData.inputparams.max - sourceCapacity) <= 0.01
end

function MimicRepeatOrders.collectSourceWaresTransportTypes(orders)
  local sourceId = MimicRepeatOrders.sourceId
  local orders = orders
  if orders == nil or type(orders) ~= "table" then
    orders = MimicRepeatOrders.getRepeatOrders(sourceId)
  end
  local transportTypes = {}
  for i = 1, #orders do
    local order = orders[i]
    local transportType = findWareTransportType(GetOrderParams(sourceId, order.idx))
    if transportType ~= nil then
      transportTypes[transportType] = true
    end
  end

  local transportTypesList = {}
  for transportType, _ in pairs(transportTypes) do
    transportTypesList[#transportTypesList + 1] = transportType
  end
  return transportTypesList
end

function MimicRepeatOrders.cloneOrdersPrepare()
  MimicRepeatOrders.targetIds = {}
  local valid, errorData = MimicRepeatOrders.ValidateSourceShip()
  if not valid then
    return false, errorData
  end
  local args = MimicRepeatOrders.args or {}
  MimicRepeatOrders.sourceId = toUniverseId(args.source)
  local targets = args.targets or {}
  local targetIds = {}
  local transportTypes = MimicRepeatOrders.collectSourceWaresTransportTypes()
  for i = 1, #targets do
    local targetId = toUniverseId(targets[i])
    local valid, errorData = MimicRepeatOrders.isValidTargetShip(targetId, transportTypes)
    if valid then
      targetIds[#targetIds + 1] = targetId
    else
      debugLog("Target ship %s is invalid: %s", getShipName(targetId), errorData and errorData.info)
      MimicRepeatOrders.removeCommander(targetId)
    end
  end
  if #targetIds == 0 then
    MimicRepeatOrders.sourceId = 0
    return false, { info = "NoValidTargets" }
  end
  MimicRepeatOrders.targetIds = targetIds
  return true
end

local function areListItemsEqualUnordered(sourceItems, targetItems)
  local counts = {}
  for j = 1, #sourceItems do
    local key = tostring(sourceItems[j])
    counts[key] = (counts[key] or 0) + 1
  end
  for j = 1, #targetItems do
    local key = tostring(targetItems[j])
    if not counts[key] or counts[key] == 0 then
      traceLog("   Target item #%s: '%s' has no matching source item", j, targetItems[j])
      return false
    end
    counts[key] = counts[key] - 1
  end
  return true
end

function MimicRepeatOrders.isOrdersEqual(sourceOrders, targetId, targetOrders, isOneShip)
  if targetId ~= nil then
    if MimicRepeatOrders.isLoopEnabled(targetId) == false then
      return false
    end
    targetOrders = MimicRepeatOrders.getRepeatOrders(targetId)
  end
  debugLog("Comparing %s source orders to %s target orders with targetId %s", #sourceOrders, #targetOrders, targetId)
  if #sourceOrders ~= #targetOrders then
    local sourceContent, targetContent = {}, {}
    for i = 1, #sourceOrders do
      sourceContent[i] = sourceOrders[i].order
    end
    for i = 1, #targetOrders do
      targetContent[i] = targetOrders[i].order
    end
    traceLog(" Source orders: [%s], Target orders: [%s]", table.concat(sourceContent, ", "), table.concat(targetContent, ", "))
    return false
  end
  for i = 1, #sourceOrders do
    local sourceOrder = sourceOrders[i]
    local targetOrder = targetOrders[i]
    traceLog(" Comparing source order %s: '%s' to target order %s: '%s'", i, sourceOrder.order, i, targetOrder.order)
    if sourceOrder.order ~= targetOrder.order then
      return false
    end
    local sourceParams = GetOrderParams(MimicRepeatOrders.sourceId, sourceOrder.idx)
    local targetParams = targetOrder.params or GetOrderParams(targetId, targetOrder.idx)
    local transportType = findWareTransportType(sourceParams)
    local sourceCapacity = transportType and MimicRepeatOrders.getCargoCapacity(MimicRepeatOrders.sourceId, transportType) or nil
    local targetCapacity = (transportType and not isOneShip) and MimicRepeatOrders.getCargoCapacity(targetId, transportType) or nil
    for paramIdx = 1, #sourceParams do
      local sourceParam = sourceParams[paramIdx]
      local targetParam = targetParams[paramIdx]
      if sourceParam.type ~= "internal" then
        local equal
        if targetParam == nil then
          equal = false
        elseif sourceParam.type == "list" then
          local sourceItems, targetItems = sourceParam.value or {}, targetParam.value or {}
          equal = #sourceItems == #targetItems and areListItemsEqualUnordered(sourceItems, targetItems)
        elseif sourceParam.type == "position" then
          equal = positionsEqual(sourceParam.value, targetParam.value)
        elseif not isOneShip and isCargoBoundParam(sourceParam, sourceCapacity) then
          local expected = (sourceCapacity > 0) and (sourceParam.value / sourceCapacity * targetCapacity) or 0
          equal = math.abs(targetParam.value - expected) <= 0.01
        else
          equal = tostring(sourceParam.value) == tostring(targetParam.value)
        end
        traceLog("  Comparing param[%s] %s (%s): source=%s target=%s -> %s",
          paramIdx, sourceParam.name, sourceParam.type, sourceParam.value, targetParam and targetParam.value, equal)
        if not equal then
          return false
        end
      end
    end
  end
  return true
end

function MimicRepeatOrders.cloneOrdersExecute(skipResult)
  debugLog("Executing clone orders from source %s to %s targets", getShipName(MimicRepeatOrders.sourceId), #MimicRepeatOrders.targetIds)
  local sourceOrders = MimicRepeatOrders.getRepeatOrders(MimicRepeatOrders.sourceId)
  local targets = MimicRepeatOrders.targetIds
  local processedOrders = 0
  for i = 1, #targets do
    local targetId = targets[i]
    debugLog("Cloning orders to target %s", getShipName(targetId))
    if MimicRepeatOrders.isOrdersEqual(sourceOrders, targetId) then
      debugLog("Target orders on %s already match source orders, skipping", getShipName(targetId))
      processedOrders = processedOrders + #sourceOrders
    else
      if not C.RemoveAllOrders(targetId) then
        debugLog("failed to clear target order queue for %s", getShipName(targetId))
      else
        C.CreateOrder(targetId, "Wait", true)
        C.EnablePlannedDefaultOrder(targetId, false)
        C.SetOrderLoop(targetId, 0, false)
        for j = 1, #sourceOrders do
          local order = sourceOrders[j]
          local orderParams = GetOrderParams(MimicRepeatOrders.sourceId, order.idx)
          local transportType = findWareTransportType(orderParams)
          local sourceCapacity = transportType and MimicRepeatOrders.getCargoCapacity(MimicRepeatOrders.sourceId, transportType) or nil
          if orderParams ~= nil and #orderParams > 0 then
            local newOrderIdx = C.CreateOrder(targetId, order.order, false)
            if newOrderIdx and newOrderIdx > 0 then
              local targetCapacity = transportType and MimicRepeatOrders.getCargoCapacity(targetId, transportType) or nil
              for paramIdx = 1, #orderParams do
                local sourceParam = orderParams[paramIdx]
                if sourceParam.type ~= "internal" then
                  if sourceParam.type == "list" then
                    for l = 1, #(sourceParam.value or {}) do
                      traceLog("   Setting list item #%s to value: '%s' at param index %s", l, sourceParam.value[l], paramIdx)
                      SetOrderParam(targetId, newOrderIdx, paramIdx, nil, sourceParam.value[l])
                    end
                  else
                    local value = sourceParam.value
                    if sourceParam.type == "money" then
                      value = value * 100
                    elseif sourceParam.type == "position" then
                      local sourcePosition = value
                      value = { ConvertStringToLuaID(tostring(sourcePosition[1])),
                        { sourcePosition[2].x, sourcePosition[2].y, sourcePosition[2].z } }
                    elseif isCargoBoundParam(sourceParam, sourceCapacity) then
                      value = (sourceCapacity > 0) and math.floor(value / sourceCapacity * targetCapacity) or 0
                    end
                    traceLog("   Setting param[%s] %s (%s) to value: '%s'", paramIdx, sourceParam.name, sourceParam.type, value)
                    SetOrderParam(targetId, newOrderIdx, paramIdx, nil, value)
                  end
                end
              end
              C.EnableOrder(targetId, newOrderIdx)
              processedOrders = processedOrders + 1
              debugLog(" Successfully created order %s on target %s", order.order, getShipName(targetId))
            else
              debugLog(" Failed to create order %s on target %s", order.order, getShipName(targetId))
            end
          end
        end
      end
    end
  end
  MimicRepeatOrders.cloneOrdersReset()

  if skipResult == nil or skipResult == false then
    if processedOrders == 0 then
      MimicRepeatOrders.reportError({ info = "NoOrdersCloned" })
    else
      MimicRepeatOrders.reportSuccess({ info = "OrdersCloned", details = string.format("%d orders cloned to %d targets", processedOrders, #targets) })
    end
  end
end

function MimicRepeatOrders.cloneOrdersReset()
  MimicRepeatOrders.sourceId = 0
  MimicRepeatOrders.targetIds = {}
end

function MimicRepeatOrders.countSubordinates()
  local sourceId = MimicRepeatOrders.sourceId
  local source = ConvertStringToLuaID(tostring(sourceId))
  local subordinatesList = GetSubordinates(source)
  return #subordinatesList
end

function MimicRepeatOrders.GetSubordinates()
  local sourceId = MimicRepeatOrders.sourceId
  local source = ConvertStringToLuaID(tostring(sourceId))
  local subordinatesList = GetSubordinates(source)
  local subordinates = {}
  debugLog(" Commander %s has %s subordinates", getShipName(sourceId), #subordinatesList)
  for j = 1, #subordinatesList do
    local subordinate = subordinatesList[j]
    local subordinateId = toUniverseId(subordinatesList[j])
    local group = GetComponentData(subordinate, "subordinategroup")
    local assignment = ffi.string(C.GetSubordinateGroupAssignment(sourceId, group))
    debugLog(" Subordinate %s is assigned to group %s with assignment %s", getShipName(subordinateId), group, assignment)
    if assignment == "assist" then
      subordinates[#subordinates + 1] = subordinateId
    end
  end
  return subordinates
end

function MimicRepeatOrders.clearRepeatOrders(skipResult, clearCommander)
  if MimicRepeatOrders.args.targets ~= nil and type(MimicRepeatOrders.args.targets) == "table" then
    MimicRepeatOrders.targetIds = {}
    for i = 1, #MimicRepeatOrders.args.targets do
      local targetId = toUniverseId(MimicRepeatOrders.args.targets[i])
      MimicRepeatOrders.targetIds[#MimicRepeatOrders.targetIds + 1] = targetId
    end
  end
  if MimicRepeatOrders.targetIds ~= nil and type(MimicRepeatOrders.targetIds) == "table" and #MimicRepeatOrders.targetIds > 0 then
    for i = 1, #MimicRepeatOrders.targetIds do
      local targetId = MimicRepeatOrders.targetIds[i]
      debugLog("Clearing repeat orders on target %s", getShipName(targetId))
      if not C.RemoveAllOrders(targetId) then
        debugLog("failed to clear target order queue for %s", getShipName(targetId))
      else
        C.CreateOrder(targetId, "Wait", true)
        C.EnablePlannedDefaultOrder(targetId, false)
        C.ResetOrderLoop(targetId)
      end
      if clearCommander == true then
        MimicRepeatOrders.removeCommander(targetId)
      end
    end
  end
  if skipResult == nil or skipResult == false then
    MimicRepeatOrders.reportSuccess({ info = "OrdersCleared", details = string.format("%d targets cleared", #MimicRepeatOrders.targetIds) })
  end
end

function MimicRepeatOrders.repeatOrdersCommandersRefresh()
  local commanders = MimicRepeatOrders.args.list or {}
  local checkSubordinates = MimicRepeatOrders.args.checkSubordinates == 1
  local repeatOrdersCommanders = {}
  debugLog("Refreshing repeat orders for %s commanders, checkSubordinates=%s", #commanders, checkSubordinates)
  for i = 1, #commanders do
    MimicRepeatOrders.cloneOrdersReset()
    local commanderId = toUniverseId(commanders[i])
    if (commanderId ~= nil) then
      MimicRepeatOrders.sourceId = commanderId
      local valid, errorData = MimicRepeatOrders.ValidateSourceShip()
      local subordinatesCount = MimicRepeatOrders.countSubordinates()
      debugLog(" Refreshing commander %s validity: %s, error: %s, subordinates: %s",
        getShipName(commanderId), valid, errorData and errorData.info, subordinatesCount)
      if valid and subordinatesCount > 0 then
        local subordinates = {}
        local commanderOrders = MimicRepeatOrders.getRepeatOrders(commanderId)
        if MimicRepeatOrders.repeatOrdersCommanders[commanderId] == nil then
          debugLog(" Commander %s caching repeat orders for the first time", getShipName(commanderId))
          repeatOrdersCommanders[commanderId] = commanderOrders
          if #commanderOrders > 0 then
            for j = 1, #commanderOrders do
              local order = repeatOrdersCommanders[commanderId][j]
              debugLog(" Commander %s has repeat order %s at index %s", getShipName(commanderId), order.order, order.idx)
              order.params = GetOrderParams(commanderId, order.idx)
            end
            subordinates = MimicRepeatOrders.GetSubordinates()
          end
        else
          debugLog(" Commander %s repeat orders already cached", getShipName(commanderId))
          if MimicRepeatOrders.isOrdersEqual(commanderOrders, nil, MimicRepeatOrders.repeatOrdersCommanders[commanderId], true) then
            debugLog(" Commander %s orders unchanged", getShipName(commanderId))
            if (checkSubordinates) then
              subordinates = MimicRepeatOrders.GetSubordinates()
            end
            repeatOrdersCommanders[commanderId] = MimicRepeatOrders.repeatOrdersCommanders[commanderId]
          else
            debugLog(" Commander %s orders changed, updating cache and subordinates", getShipName(commanderId))
            repeatOrdersCommanders[commanderId] = commanderOrders
            for j = 1, #commanderOrders do
              local order = repeatOrdersCommanders[commanderId][j]
              debugLog(" Commander %s has repeat order %s at index %s", getShipName(commanderId), order.order, order.idx)
              order.params = GetOrderParams(commanderId, order.idx)
            end
            subordinates = MimicRepeatOrders.GetSubordinates()
          end
        end
        if #subordinates > 0 then
          debugLog(" Commander %s has %s subordinates to check", getShipName(commanderId), #subordinates)
          MimicRepeatOrders.targetIds = {}
          local transportTypes = MimicRepeatOrders.collectSourceWaresTransportTypes(commanderOrders)
          for j = 1, #subordinates do
            local valid, errorData = MimicRepeatOrders.isValidTargetShip(subordinates[j], transportTypes)
            if not valid then
              debugLog("  Subordinate %s is invalid, removing from list", getShipName(subordinates[j]))
              MimicRepeatOrders.removeCommander(subordinates[j])
            else
              MimicRepeatOrders.targetIds[#MimicRepeatOrders.targetIds + 1] = subordinates[j]
            end
          end
          MimicRepeatOrders.cloneOrdersExecute(true)
        end
      else
        commanders[i] = 0
        if subordinatesCount > 0 then
          debugLog(" Commander %s is invalid, skipping %s subordinates", getShipName(commanderId), subordinatesCount)
          MimicRepeatOrders.targetIds = MimicRepeatOrders.GetSubordinates()
          MimicRepeatOrders.clearRepeatOrders(true, true)
        end
      end
    end
  end
  MimicRepeatOrders.repeatOrdersCommanders = repeatOrdersCommanders
  MimicRepeatOrders.cloneOrdersReset()
  MimicRepeatOrders.reportSuccess()
end

function MimicRepeatOrders.addOrderToQueue()
  local args = MimicRepeatOrders.args or {}
  if args.ship == nil then
    MimicRepeatOrders.reportError({ info = "missing_ship" })
    return
  end

  local shipId = toUniverseId(args.ship)
  if shipId == 0 then
    MimicRepeatOrders.reportError({ info = "invalid_ship" })
    return
  end

  local order = args.order
  if order == nil or type(order) ~= "string" then
    MimicRepeatOrders.reportError({ info = "missing_order" })
    return
  end

  debugLog("Adding order %s to ship %s", order, getShipName(shipId))

  local params = args.params
  if params == nil or type(params) ~= "table" then
    MimicRepeatOrders.reportError({ info = "missing_params" })
    return
  end

  local newOrderIdx = C.CreateOrder(shipId, order, false)
  if newOrderIdx and newOrderIdx > 0 then
    -- Sets whatever the caller provides by name, leaving anything not provided at
    -- its engine default -- no curated required-param list anymore.
    local orderParams = GetOrderParams(shipId, newOrderIdx)
    for paramIdx = 1, #orderParams do
      local paramData = orderParams[paramIdx]
      local value = params[paramData.name]
      if paramData.type ~= "internal" and value ~= nil then
        if paramData.type == "list" then
          for k = 1, #value do
            traceLog(" Setting order param[%s] %s to value: '%s' as part of list", paramIdx, paramData.name, value[k])
            SetOrderParam(shipId, newOrderIdx, paramIdx, nil, value[k])
          end
        else
          traceLog(" Setting order param[%s] %s to value: '%s'", paramIdx, paramData.name, value)
          SetOrderParam(shipId, newOrderIdx, paramIdx, nil, value)
        end
      end
    end
    C.EnableOrder(shipId, newOrderIdx)
    debugLog(" Successfully created order %s on target %s", order, getShipName(shipId))
  else
    debugLog(" Failed to create order %s on target %s", order, getShipName(shipId))
    MimicRepeatOrders.reportError({ info = "invalid_order" })
  end
end

function MimicRepeatOrders.ProcessRequest(_, _)
  if not MimicRepeatOrders.getArgs() then
    debugLog("ProcessRequest invoked without args or invalid args")
    MimicRepeatOrders.reportError({ info = "missing_args" })
    return
  end
  debugLog("ProcessRequest received command: %s", MimicRepeatOrders.args.command)
  if MimicRepeatOrders.args.command == "clone_orders" then
    local valid, errorData = MimicRepeatOrders.cloneOrdersPrepare()
    debugLog(" cloneOrdersPrepare returned valid=%s, error=%s", valid, errorData and errorData.info)
    if valid then
      MimicRepeatOrders.cloneOrdersExecute()
    else
      MimicRepeatOrders.reportError(errorData)
    end
  elseif MimicRepeatOrders.args.command == "refresh_commanders" then
    MimicRepeatOrders.repeatOrdersCommandersRefresh()
  elseif MimicRepeatOrders.args.command == "clear_orders" then
    MimicRepeatOrders.clearRepeatOrders(false, false)
  elseif MimicRepeatOrders.args.command == "add_order_to_queue" then
    MimicRepeatOrders.addOrderToQueue()
  else
    debugLog("ProcessRequest received unknown command: %s", MimicRepeatOrders.args.command)
    MimicRepeatOrders.reportError({ info = "UnknownCommand" })
  end
end

function MimicRepeatOrders.Init()
  getPlayerId()
  ---@diagnostic disable-next-line: undefined-global
  RegisterEvent("MimicRepeatOrders.Request", MimicRepeatOrders.ProcessRequest)
  ---@diagnostic disable-next-line: undefined-global
  RegisterEvent("MimicRepeatOrders.DebugLevelChanged", MimicRepeatOrders.onDebugLevelChanged)
  MimicRepeatOrders.onDebugLevelChanged()
  MimicRepeatOrders.mapMenu = Lib.Get_Egosoft_Menu("MapMenu")
  debugLog("MapMenu is %s", MimicRepeatOrders.mapMenu)
  MimicRepeatOrders.loopOrdersSkillLimit = C.GetOrderLoopSkillLimit() * 3
  SetNPCBlackboard(MimicRepeatOrders.playerId, "$MimicRepeatOrdersLoopOrdersSkillLimit", MimicRepeatOrders.loopOrdersSkillLimit)
  AddUITriggeredEvent("MimicRepeatOrders", "Reloaded")
end

Register_Require_With_Init("extensions.mimic_repeat_orders.ui.mimic_repeat_orders", MimicRepeatOrders, MimicRepeatOrders.Init)

return MimicRepeatOrders
