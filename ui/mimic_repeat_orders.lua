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
  validOrders = {
    SingleBuy            = {
      enabled = false,
      weight = 1,
      name = "",
      wareIdx = 1,
      params = {
        ware = { idx = 1 },
        locations = { idx = 4, converter = "listOfString" },
        maxamount = { idx = 5, converter = "viaCargo" },
        pricethreshold = { idx = 7, converter = "price" }
      },
      paramsOrder = { "ware", "locations", "maxamount", "pricethreshold" }
    },
    SingleSell           = {
      enabled = false,
      weight = 1,
      name = "",
      wareIdx = 1,
      params = {
        ware = { idx = 1 },
        locations = { idx = 4, converter = "listOfString" },
        maxamount = { idx = 5, converter = "viaCargo" },
        pricethreshold = { idx = 7, converter = "price" }
      },
      paramsOrder = { "ware", "locations", "maxamount", "pricethreshold" }
    },
    MiningPlayer         = {
      enabled = false,
      weight = 1,
      name = "",
      wareIdx = 3,
      params = {
        destination = { idx = 1, converter = "position" },
        ware = { idx = 3 }
      },
      paramsOrder = { "destination", "ware" }
    },
    MiningPlayerSector   = {
      enabled = false,
      weight = 1,
      name = "",
      wareIdx = 2,
      params = {
        location = { idx = 1, compare = "asString" },
        ware = { idx = 2 }
      },
      paramsOrder = { "location", "ware" }
    },
    CollectDropsInRadius = {
      enabled = false,
      weight = 2,
      name = "",
      wareIdx = nil,
      params = {
        destination = { idx = 1, converter = "position" },
      },
      paramsOrder = { "destination" }
    },
    DepositInventory = {
      enabled = false,
      weight = 1,
      name = "",
      wareIdx = nil,
      params = {
        destination = { idx = 1, compare = "asObjectId" },
      },
      paramsOrder = { "destination" }
    },
    SalvageInRadius = {
      enabled = false,
      weight = 1,
      name = "",
      wareIdx = nil,
      params = {
        destination = { idx = 1, converter = "position" },
        radius = { idx = 3 },
      },
      paramsOrder = { "destination", "radius" }
    },
    SalvageDeliver_NoTrade = {
      enabled = false,
      weight = 1,
      name = "",
      wareIdx = nil,
      params = {
        destination = { idx = 1, compare = "asObjectId" },
      },
      paramsOrder = { "destination" }
    },
    ExploreUpdate = {
      enabled = false,
      weight = 2,
      name = "",
      wareIdx = nil,
      params = {
        destination = { idx = 2, converter = "position" },
        radius = { idx = 3 },
      },
      paramsOrder = { "destination", "radius" }
    },
  },
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

function MimicRepeatOrders.ValidateSourceShipAndCleanupOrders()
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
  local ordersToRemove = {}
  local validOrders = {}
  local validOrdersCount = 0
  for i = 1, #orders do
    if MimicRepeatOrders.validOrders[orders[i].order] == nil or MimicRepeatOrders.validOrders[orders[i].order].enabled == false then
      ordersToRemove[#ordersToRemove + 1] = orders[i]
    else
      if validOrders[orders[i].order] ~= true then
        validOrders[orders[i].order] = true
        local weight = MimicRepeatOrders.validOrders[orders[i].order].weight or 1
        validOrdersCount = validOrdersCount + weight
      end
    end
  end
  debugLog("Source ship %s has %s valid repeat orders and %s invalid repeat orders to remove from a total of %s repeat orders",
    getShipName(sourceId), validOrdersCount, #ordersToRemove, #orders)
  if (validOrdersCount < 2) then
    return false, { info = "NoEnoughValidRepeatOrders" }
  end
  if #ordersToRemove > 0 then
    debugLog("Source ship %s has %s invalid repeat orders to remove", getShipName(sourceId), #ordersToRemove)
    for i = #ordersToRemove, 1, -1 do
      local order = ordersToRemove[i]
      traceLog(" Removing invalid repeat order %s at index %s", order.order, order.idx)
      C.RemoveOrder(sourceId, order.idx, true, false)
    end
  end
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

function MimicRepeatOrders.collectSourceWaresTransportTypes(orders)
  local sourceId = MimicRepeatOrders.sourceId
  local orders = orders
  if orders == nil or type(orders) ~= "table" then
    orders = MimicRepeatOrders.getRepeatOrders(sourceId)
  end
  local wares = {}
  for i = 1, #orders do
    local order = orders[i]
    if MimicRepeatOrders.validOrders[order.order] ~= nil then
      local params = GetOrderParams(sourceId, order.idx)
      local wareIdx = MimicRepeatOrders.validOrders[order.order].wareIdx
      if wareIdx ~= nil and params[wareIdx] ~= nil then
        local wareId = params[wareIdx].value
        wares[wareId] = true
      end
    end
  end

  local transportTypes = {}
  for wareId, _ in pairs(wares) do
    local transportType = GetWareData(wareId, "transport")
    if transportType ~= nil and transportTypes[transportType] == nil then
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
  local valid, errorData = MimicRepeatOrders.ValidateSourceShipAndCleanupOrders()
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
    local paramsDef = MimicRepeatOrders.validOrders[sourceOrder.order].params
    local wareIdx = MimicRepeatOrders.validOrders[sourceOrder.order].wareIdx
    if paramsDef ~= nil then
      for paramName, paramDef in pairs(paramsDef) do
        if paramDef.converter == "listOfString" then
          local sourceItems = sourceParams[paramDef.idx].value or {}
          local targetItems = targetParams[paramDef.idx].value or {}
          traceLog("  Comparing source items: '%s' to target items: '%s'", #sourceItems, #targetItems)
          if #sourceItems ~= #targetItems then
            traceLog("   Source items count: '%s' does not match target items count: '%s'", #sourceItems, #targetItems)
            return false
          end
          if not areListItemsEqualUnordered(sourceItems, targetItems) then
            traceLog("   Target items do not match source items")
            return false
          end
        else
          local sourceValue = sourceParams[paramDef.idx].value
          local targetValue = targetParams[paramDef.idx].value
          traceLog("  Comparing source param: '%s' value: '%s' to target value: '%s'", paramName, sourceValue, targetValue)
          if paramDef.converter == "viaCargo" then
            if sourceValue > 0 and targetValue == 0 then
              traceLog("   Source value: '%s' does not match target value '%s'", sourceValue, targetValue)
              return false
            elseif sourceValue == 0 and targetValue > 0 then
              traceLog("   Source value: '%s' does not match target value: '%s'", sourceValue, targetValue)
              return false
            elseif sourceValue == 0 and targetValue > 0 then
              traceLog("   Source value: '%s' does not match target value: '%s'", sourceValue, targetValue)
              return false
            elseif sourceValue == 0 and targetValue > 0 then
              traceLog("   Source value: '%s' does not match target value: '%s'", sourceValue, targetValue)
              return false
            elseif sourceValue > 0 and targetValue > 0 then
              traceLog("   isOneShip: '%s' source value: '%s' vs target value: '%s'", isOneShip, sourceValue, targetValue)
              if isOneShip and sourceValue ~= targetValue then
                traceLog("   Is One Ship. Source value: '%s' does not match target value: '%s'", sourceValue, targetValue)
                return false
              end
              if not isOneShip and wareIdx ~= nil then
                local sourceWareId = sourceParams[wareIdx].value
                local targetWareId = targetParams[wareIdx].value
                if sourceWareId ~= targetWareId then
                  traceLog("   Source ware ID: '%s' does not match target ware ID: '%s'", sourceWareId, targetWareId)
                  return false
                end
                local transporttype = GetWareData(sourceWareId, "transport")
                local sourceCargoCapacity = MimicRepeatOrders.getCargoCapacity(MimicRepeatOrders.sourceId, transporttype)
                local targetCargoCapacity = MimicRepeatOrders.getCargoCapacity(targetId, transporttype)
                traceLog("   Transport type: '%s' source cargo capacity: '%s' vs target cargo capacity: '%s'",
                  transporttype, sourceCargoCapacity, targetCargoCapacity)
                local calculatedTargetValue = (sourceCargoCapacity > 0) and math.floor(sourceValue * targetCargoCapacity / sourceCargoCapacity) or 0
                traceLog("   Target value: '%s' vs calculated target value: '%s'", targetValue, calculatedTargetValue)

                if math.abs(targetValue - calculatedTargetValue) > 0.01 then
                  traceLog("   Target value: '%s' does not match calculated target value: '%s'", targetValue, calculatedTargetValue)
                  return false
                end
              end
            end
          elseif paramDef.converter == "position" then
            local sourceRefObject = sourceValue[1]
            local targetRefObject = targetValue[1]
            traceLog("   Comparing source position ref object: '%s' to target ref object: '%s'", sourceRefObject, targetRefObject)
            if tostring(sourceRefObject) ~= tostring(targetRefObject) then
              traceLog("   Source position ref object: '%s' does not match target ref object: '%s'", sourceRefObject, targetRefObject)
              return false
            end
            local sourceOffset = sourceValue[2]
            local targetOffset = targetValue[2]
            local axises = { "x", "y", "z" }
            for j = 1, 3 do
              local axis = axises[j]
              traceLog("   Comparing source position at axis %s '%s' to target position '%s'", axis, sourceOffset[axis], targetOffset[axis])
              if math.abs(sourceOffset[axis] - targetOffset[axis]) > 0.01 then
                traceLog("   Source position at axis %s '%s' does not match target position '%s'", axis, sourceOffset[axis], targetOffset[axis])
                return false
              end
            end
          else
            traceLog("   Comparing source value: '%s' to target value: '%s'", sourceValue, targetValue)
            if (paramDef.compare == "asString") then
              sourceValue = tostring(sourceValue)
              targetValue = tostring(targetValue)
            elseif (paramDef.compare == "asObjectId") then
              sourceValue = ConvertStringTo64Bit(tostring(sourceValue))
              targetValue = ConvertStringTo64Bit(tostring(targetValue))
            end
            if sourceValue ~= targetValue then
              traceLog("   Source value '%s' does not match target value '%s'", sourceValue, targetValue)
              return false
            end
          end
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
          local orderDef = MimicRepeatOrders.validOrders[order.order]
          if orderDef == nil or not orderDef.enabled then
            debugLog(" Unexpected not valid order %s", order.order)
          else
            local orderParams = GetOrderParams(MimicRepeatOrders.sourceId, order.idx)
            local orderParamsDefs = orderDef.params
            local orderParamsDefsOrder = orderDef.paramsOrder
            if (orderParams ~= nil and #orderParams > 0 and orderParamsDefs ~= nil and orderParamsDefsOrder ~= nil and #orderParamsDefsOrder > 0) then
              local newOrderIdx = C.CreateOrder(targetId, order.order, false)
              if newOrderIdx and newOrderIdx > 0 then
                for k = 1, #orderParamsDefsOrder do
                  local orderParamName = orderParamsDefsOrder[k]
                  local orderParamDef = orderParamsDefs[orderParamName]
                  traceLog(" Processing order param %s with definition %s", orderParamName, orderParamDef)
                  local orderParam = orderParams[orderParamDef.idx]
                  traceLog("  Setting order param[%s] %s to value: '%s' with definition %s and converter %s",
                    orderParamDef.idx, orderParam.name, orderParam.value, orderParamDef, orderParamDef and orderParamDef.converter)
                  if orderParamDef.converter == "listOfString" then
                    for l = 1, #orderParam.value do
                      traceLog("   Setting list item #%s to value: '%s' at order index %s param index %s",
                        l, orderParam.value[l], newOrderIdx, orderParamDef.idx)
                      SetOrderParam(targetId, newOrderIdx, orderParamDef.idx, nil, orderParam.value[l])
                    end
                  else
                    local value = orderParam.value
                    if orderParamDef.converter == "viaCargo" then
                      if value > 0 then
                        local wareIdx = orderDef.wareIdx
                        if (wareIdx ~= nil) then
                          local wareId = orderParams[wareIdx].value
                          local transporttype = GetWareData(wareId, "transport")
                          local sourceCargoCapacity = MimicRepeatOrders.getCargoCapacity(MimicRepeatOrders.sourceId, transporttype)
                          local targetCargoCapacity = MimicRepeatOrders.getCargoCapacity(targetId, transporttype)
                          traceLog("   Transport type: '%s' source cargo capacity: '%s' vs target cargo capacity: '%s'",
                            transporttype, sourceCargoCapacity, targetCargoCapacity)
                          value = (sourceCargoCapacity > 0) and math.floor(orderParam.value / sourceCargoCapacity * targetCargoCapacity) or 0
                          traceLog("   Converted viaCargo value: '%s' for ware: '%s'", value, wareId)
                        end
                      end
                    elseif orderParamDef.converter == "price" then
                      value = orderParam.value * 100
                    elseif orderParamDef.converter == "position" then
                      local sourcePosition = orderParam.value
                      local targetPosition = {}
                      targetPosition[1] = ConvertStringToLuaID(tostring(sourcePosition[1]))
                      traceLog("   Preparing position ref object: %s", targetPosition[1])
                      targetPosition[2] = {}
                      targetPosition[2][1] = sourcePosition[2].x
                      targetPosition[2][2] = sourcePosition[2].y
                      targetPosition[2][3] = sourcePosition[2].z
                      traceLog("   Preparing position offset: x=%.2f, y=%.2f, z=%.2f", targetPosition[2][1], targetPosition[2][2], targetPosition[2][3])
                      value = targetPosition
                    end
                    traceLog("   Final value to set: '%s' at order index %s param index %s", value, newOrderIdx, orderParamDef.idx)
                    SetOrderParam(targetId, newOrderIdx, orderParamDef.idx, nil, value)
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
      local valid, errorData = MimicRepeatOrders.ValidateSourceShipAndCleanupOrders()
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

  local orderDef = MimicRepeatOrders.validOrders[order]
  if orderDef == nil or orderDef.enabled == false then
    MimicRepeatOrders.reportError({ info = "invalid_order" })
    return
  end

  debugLog("Adding order %s to ship %s", order, getShipName(shipId))

  local orderParamsDefs = orderDef.params
  local orderParamsDefsOrder = orderDef.paramsOrder

  local params = args.params
  if params == nil or type(params) ~= "table" then
    MimicRepeatOrders.reportError({ info = "missing_params" })
    return
  end


  for i = 1, #orderParamsDefsOrder do
    local key = orderParamsDefsOrder[i]
    if params[key] == nil then
      MimicRepeatOrders.reportError({ info = "missing_param", detail = "Missing parameter: " .. tostring(key) })
      return
    end
    traceLog(" Param %s value: '%s'", key, params[key])
  end


  local newOrderIdx = C.CreateOrder(shipId, order, false)
  if newOrderIdx and newOrderIdx > 0 then
    for i = 1, #orderParamsDefsOrder do
      local name = orderParamsDefsOrder[i]
      local orderParamDef = orderParamsDefs[name]
      local value = params[name]
      if orderParamDef ~= nil and value ~= nil then
        if orderParamDef.converter == "listOfString" then
          for k = 1, #value do
            traceLog(" Setting order param[%s] %s to value: '%s' as part of listOfString", orderParamDef.idx, name, value[k])
            SetOrderParam(shipId, newOrderIdx, orderParamDef.idx, nil, value[k])
          end
        else
          traceLog(" Setting order param[%s] %s to value: '%s'", orderParamDef.idx, name, value)
          SetOrderParam(shipId, newOrderIdx, orderParamDef.idx, nil, value)
        end
      end
    end
    C.EnableOrder(shipId, newOrderIdx)
    debugLog(" Successfully created order %s on target %s", order, getShipName(shipId))
  else
    debugLog(" Failed to create order %s on target %s", order, getShipName(shipId))
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

function MimicRepeatOrders.OrderNamesCollect()
  for orderDef, _ in pairs(MimicRepeatOrders.validOrders) do
    local buf = ffi.new("OrderDefinition")
    local found = C.GetOrderDefinition(buf, orderDef)
    if found then
      local orderName = ffi.string(buf.name)
      MimicRepeatOrders.validOrders[orderDef].name = orderName
      MimicRepeatOrders.validOrders[orderDef].enabled = true
      debugLog("Order definition %s resolved to name %s", orderDef, MimicRepeatOrders.validOrders[orderDef].name)
    else
      debugLog("Order definition %s could not be resolved", orderDef)
    end
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
  MimicRepeatOrders.OrderNamesCollect()
  MimicRepeatOrders.loopOrdersSkillLimit = C.GetOrderLoopSkillLimit() * 3
  SetNPCBlackboard(MimicRepeatOrders.playerId, "$MimicRepeatOrdersLoopOrdersSkillLimit", MimicRepeatOrders.loopOrdersSkillLimit)
  AddUITriggeredEvent("MimicRepeatOrders", "Reloaded")
end

Register_Require_With_Init("extensions.mimic_repeat_orders.ui.mimic_repeat_orders", MimicRepeatOrders, MimicRepeatOrders.Init)

return MimicRepeatOrders
