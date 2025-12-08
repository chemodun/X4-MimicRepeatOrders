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
  },
  sourceId = 0,
  loopOrdersSkillLimit = 0,
  targetIds = {},
  repeatOrdersCommanders = {},
}


local Lib = require("extensions.sn_mod_support_apis.ui.Library")

local debugTraceLevel = "debug"

debugTraceLevel = "trace"

local function debugTrace(level, message)
  local text = "MimicRepeatOrders: " .. message
  if type(DebugError) == "function" then
    if debugTraceLevel == "trace" or level == debugTraceLevel then
      DebugError(text)
    end
  end
end

local function getPlayerId()
  local current = C.GetPlayerID()
  if current == nil or current == 0 then
    return
  end

  local converted = ConvertStringTo64Bit(tostring(current))
  if converted ~= 0 and converted ~= MimicRepeatOrders.playerId then
    debugTrace("debug", "updating player_id to " .. tostring(converted))
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
  debugTrace("debug", "recordResult called for command " .. tostring(data and data.command) .. " with result " .. tostring(data and data.result))
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
  debugTrace("debug",
    "Source ship " ..
    getShipName(sourceId) ..
    " has " ..
    tostring(validOrdersCount) ..
    " valid repeat orders and " .. tostring(#ordersToRemove) .. " invalid repeat orders to remove from a total of " .. tostring(#orders) .. " repeat orders")
  if (validOrdersCount < 2) then
    return false, { info = "NoEnoughValidRepeatOrders" }
  end
  if #ordersToRemove > 0 then
    debugTrace("debug", "Source ship " .. getShipName(sourceId) .. " has " .. tostring(#ordersToRemove) .. " invalid repeat orders to remove")
    for i = #ordersToRemove, 1, -1 do
      local order = ordersToRemove[i]
      debugTrace("trace", " Removing invalid repeat order " .. tostring(order.order) .. " at index " .. tostring(order.idx))
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
  debugTrace("trace", "Target ship " .. getShipName(targetId) .. " has AI pilot skill " .. tostring(aiPilotSkill) .. ", required is " .. tostring(loopSkill))
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
    debugTrace("debug", "getArgs unable to resolve player id")
  else
    local list = GetNPCBlackboard(MimicRepeatOrders.playerId, "$MimicRepeatOrdersRequest")
    if type(list) == "table" and #list > 0 then
      debugTrace("debug", "getArgs retrieved " .. tostring(#list) .. " entries from blackboard")
      for i = 1, #list do
        debugTrace("trace", " getArgs entry " .. tostring(i) .. ": " .. tostring(list[i]))
        MimicRepeatOrders.queueArgs[#MimicRepeatOrders.queueArgs + 1] = list[i]
      end
      SetNPCBlackboard(MimicRepeatOrders.playerId, "$MimicRepeatOrdersRequest", nil)
    elseif list ~= nil then
      debugTrace("debug", "getArgs received non-table payload of type " .. type(list))
    else
      debugTrace("debug", "getArgs found no blackboard entries for player " .. tostring(MimicRepeatOrders.playerId))
    end
  end
  if #MimicRepeatOrders.queueArgs > 0 then
    MimicRepeatOrders.args = MimicRepeatOrders.queueArgs[1]
    table.remove(MimicRepeatOrders.queueArgs, 1)
    debugTrace("debug",
      "getArgs processing command " ..
      tostring(MimicRepeatOrders.args and MimicRepeatOrders.args.command) .. " with " .. tostring(#MimicRepeatOrders.queueArgs) .. " remaining in queue")
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
      debugTrace("debug", "Target ship " .. getShipName(targetId) .. " is invalid: " .. tostring(errorData and errorData.info))
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

function MimicRepeatOrders.isOrdersEqual(sourceOrders, targetId, targetOrders, isOneShip)
  if targetId ~= nil then
    if MimicRepeatOrders.isLoopEnabled(targetId) == false then
      return false
    end
    targetOrders = MimicRepeatOrders.getRepeatOrders(targetId)
  end
  debugTrace("debug",
    "Comparing " .. tostring(#sourceOrders) .. " source orders to " .. tostring(#targetOrders) .. " target orders with targetId " .. tostring(targetId))
  if #sourceOrders ~= #targetOrders then
    return false
  end
  for i = 1, #sourceOrders do
    local sourceOrder = sourceOrders[i]
    local targetOrder = targetOrders[i]
    debugTrace("trace",
      " Comparing source order " ..
      tostring(i) .. ": '" .. tostring(sourceOrder.order) .. "' to target order " .. tostring(i) .. ": '" .. tostring(targetOrder.order) .. "'")
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
          debugTrace("trace", "  Comparing source items: '" .. tostring(#sourceItems) .. "' to target items: '" .. tostring(#targetItems) .. "'")
          if #sourceItems ~= #targetItems then
            debugTrace("trace", "   Source items count: '" .. tostring(#sourceItems) .. "' does not match target items count: '" .. tostring(#targetItems) .. "'")
            return false
          end
          for j = 1, #sourceItems do
            debugTrace("trace",
              "   Comparing source item #" ..
              tostring(j) ..
              ": '" ..
              tostring(sourceItems[j]) ..
              "' to target item #" ..
              tostring(j) .. ": '" .. tostring(targetItems[j]) .. "' = " .. tostring(tostring(sourceItems[j]) == tostring(targetItems[j])))
            if tostring(sourceItems[j]) ~= tostring(targetItems[j]) then
              debugTrace("trace",
                "   Source item #" ..
                tostring(j) .. ": '" .. tostring(sourceItems[j]) .. "' does not match target item #" .. tostring(j) .. ": '" .. tostring(targetItems[j]) .. "'")
              return false
            end
          end
        else
          local sourceValue = sourceParams[paramDef.idx].value
          local targetValue = targetParams[paramDef.idx].value
          debugTrace("trace",
            "  Comparing source param: '" ..
            tostring(paramName) .. "' value: '" .. tostring(sourceValue) .. "' to target value: '" .. tostring(targetValue) .. "'")
          if paramDef.converter == "viaCargo" then
            if sourceValue > 0 and targetValue == 0 then
              debugTrace("trace", "   Source value: '" .. tostring(sourceValue) .. "' does not match target value '" .. tostring(targetValue) .. "'")
              return false
            elseif sourceValue == 0 and targetValue > 0 then
              debugTrace("trace", "   Source value: '" .. tostring(sourceValue) .. "' does not match target value: '" .. tostring(targetValue) .. "'")
              return false
            elseif sourceValue == 0 and targetValue > 0 then
              debugTrace("trace", "   Source value: '" .. tostring(sourceValue) .. "' does not match target value: '" .. tostring(targetValue) .. "'")
              return false
            elseif sourceValue == 0 and targetValue > 0 then
              debugTrace("trace", "   Source value: '" .. tostring(sourceValue) .. "' does not match target value: '" .. tostring(targetValue) .. "'")
              return false
            elseif sourceValue > 0 and targetValue > 0 then
              debugTrace("trace",
                "   isOneShip: '" ..
                tostring(isOneShip) .. "' source value: '" .. tostring(sourceValue) .. "' vs target value: '" .. tostring(targetValue) .. "'")
              if isOneShip and sourceValue ~= targetValue then
                debugTrace("trace",
                  "   Is One Ship. Source value: '" .. tostring(sourceValue) .. "' does not match target value: '" .. tostring(targetValue) .. "'")
                return false
              end
              if not isOneShip and wareIdx ~= nil then
                local sourceWareId = sourceParams[wareIdx].value
                local targetWareId = targetParams[wareIdx].value
                if sourceWareId ~= targetWareId then
                  debugTrace("trace", "   Source ware ID: '" .. tostring(sourceWareId) .. "' does not match target ware ID: '" .. tostring(targetWareId) .. "'")
                  return false
                end
                local transporttype = GetWareData(sourceWareId, "transport")
                local sourceCargoCapacity = MimicRepeatOrders.getCargoCapacity(MimicRepeatOrders.sourceId, transporttype)
                local targetCargoCapacity = MimicRepeatOrders.getCargoCapacity(targetId, transporttype)
                debugTrace("trace",
                  "   Transport type: '" ..
                  tostring(transporttype) ..
                  "' source cargo capacity: '" .. tostring(sourceCargoCapacity) .. "' vs target cargo capacity: '" .. tostring(targetCargoCapacity) .. "'")
                local calculatedTargetValue = (sourceCargoCapacity > 0) and math.floor(sourceValue * targetCargoCapacity / sourceCargoCapacity) or 0
                debugTrace("trace", "   Target value: '" .. tostring(targetValue) .. "' vs calculated target value: '" .. tostring(calculatedTargetValue) .. "'")

                if math.abs(targetValue - calculatedTargetValue) > 0.01 then
                  debugTrace("trace",
                    "   Target value: '" .. tostring(targetValue) .. "' does not match calculated target value: '" .. tostring(calculatedTargetValue) .. "'")
                  return false
                end
              end
            end
          elseif paramDef.converter == "position" then
            local sourceRefObject = sourceValue[1]
            local targetRefObject = targetValue[1]
            debugTrace("trace",
              "   Comparing source position ref object: '" .. tostring(sourceRefObject) .. "' to target ref object: '" .. tostring(targetRefObject) .. "'")
            if tostring(sourceRefObject) ~= tostring(targetRefObject) then
              debugTrace("trace",
                "   Source position ref object: '" .. tostring(sourceRefObject) .. "' does not match target ref object: '" .. tostring(targetRefObject) .. "'")
              return false
            end
            local sourceOffset = sourceValue[2]
            local targetOffset = targetValue[2]
            local axises = { "x", "y", "z" }
            for j = 1, 3 do
              local axis = axises[j]
              debugTrace("trace",
                "   Comparing source position at axis " ..
                tostring(axis) .. " '" .. tostring(sourceOffset[axis]) .. "' to target position '" .. tostring(targetOffset[axis]) .. "'")
              if math.abs(sourceOffset[axis] - targetOffset[axis]) > 0.01 then
                debugTrace("trace",
                  "   Source position at axis " ..
                  tostring(axis) .. " '" .. tostring(sourceOffset[axis]) .. "' does not match target position '" .. tostring(targetOffset[axis]) .. "'")
                return false
              end
            end
          else
            debugTrace("trace", "   Comparing source value: '" .. tostring(sourceValue) .. "' to target value: '" .. tostring(targetValue) .. "'")
            if (paramDef.compare == "asString") then
              sourceValue = tostring(sourceValue)
              targetValue = tostring(targetValue)
            elseif (paramDef.compare == "asObjectId") then
              sourceValue = ConvertStringTo64Bit(tostring(sourceValue))
              targetValue = ConvertStringTo64Bit(tostring(targetValue))
            end
            if sourceValue ~= targetValue then
              debugTrace("trace", "   Source value '" .. tostring(sourceValue) .. "' does not match target value '" .. tostring(targetValue) .. "'")
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
  debugTrace("debug",
    "Executing clone orders from source " .. getShipName(MimicRepeatOrders.sourceId) .. " to " .. tostring(#MimicRepeatOrders.targetIds) .. " targets")
  local sourceOrders = MimicRepeatOrders.getRepeatOrders(MimicRepeatOrders.sourceId)
  local targets = MimicRepeatOrders.targetIds
  local processedOrders = 0
  for i = 1, #targets do
    local targetId = targets[i]
    debugTrace("debug", "Cloning orders to target " .. getShipName(targetId))
    if MimicRepeatOrders.isOrdersEqual(sourceOrders, targetId) then
      debugTrace("debug", "Target orders on " .. getShipName(targetId) .. " already match source orders, skipping")
      processedOrders = processedOrders + #sourceOrders
    else
      if not C.RemoveAllOrders(targetId) then
        debugTrace("debug", "failed to clear target order queue for " .. getShipName(targetId))
      else
        C.CreateOrder(targetId, "Wait", true)
        C.EnablePlannedDefaultOrder(targetId, false)
        C.SetOrderLoop(targetId, 0, false)
        for j = 1, #sourceOrders do
          local order = sourceOrders[j]
          local orderDef = MimicRepeatOrders.validOrders[order.order]
          if orderDef == nil or not orderDef.enabled then
            debugTrace("debug", " Unexpected not valid order " .. tostring(order.order))
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
                  debugTrace("trace", " Processing order param " .. tostring(orderParamName) .. " with definition " .. tostring(orderParamDef))
                  local orderParam = orderParams[orderParamDef.idx]
                  debugTrace("trace",
                    "  Setting order param[" ..
                    tostring(orderParamDef.idx) ..
                    "] " ..
                    tostring(orderParam.name) ..
                    " to value: '" ..
                    tostring(orderParam.value) ..
                    "' with definition " .. tostring(orderParamDef) .. " and converter " .. tostring(orderParamDef and orderParamDef.converter))
                  if orderParamDef.converter == "listOfString" then
                    for l = 1, #orderParam.value do
                      debugTrace("trace",
                        "   Setting list item #" ..
                        tostring(l) ..
                        " to value: '" ..
                        tostring(orderParam.value[l]) .. "' at order index " .. tostring(newOrderIdx) .. " param index " .. tostring(orderParamDef.idx))
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
                          debugTrace("trace",
                            "   Transport type: '" ..
                            tostring(transporttype) ..
                            "' source cargo capacity: '" ..
                            tostring(sourceCargoCapacity) .. "' vs target cargo capacity: '" .. tostring(targetCargoCapacity) .. "'")
                          value = (sourceCargoCapacity > 0) and math.floor(orderParam.value / sourceCargoCapacity * targetCargoCapacity) or 0
                          debugTrace("trace", "   Converted viaCargo value: '" .. tostring(value) .. "' for ware: '" .. tostring(wareId) .. "'")
                        end
                      end
                    elseif orderParamDef.converter == "price" then
                      value = orderParam.value * 100
                    elseif orderParamDef.converter == "position" then
                      local sourcePosition = orderParam.value
                      local targetPosition = {}
                      targetPosition[1] = ConvertStringToLuaID(tostring(sourcePosition[1]))
                      debugTrace("trace", "   Preparing position ref object: " .. tostring(targetPosition[1]))
                      targetPosition[2] = {}
                      targetPosition[2][1] = sourcePosition[2].x
                      targetPosition[2][2] = sourcePosition[2].y
                      targetPosition[2][3] = sourcePosition[2].z
                      debugTrace("trace",
                        string.format("   Preparing position offset: x=%.2f, y=%.2f, z=%.2f", targetPosition[2][1], targetPosition[2][2], targetPosition[2][3]))
                      value = targetPosition
                    end
                    debugTrace("trace",
                      "   Final value to set: '" ..
                      tostring(value) .. "' at order index " .. tostring(newOrderIdx) .. " param index " .. tostring(orderParamDef.idx))
                    SetOrderParam(targetId, newOrderIdx, orderParamDef.idx, nil, value)
                  end
                end
                C.EnableOrder(targetId, newOrderIdx)
                processedOrders = processedOrders + 1
                debugTrace("debug", " Successfully created order " .. tostring(order.order) .. " on target " .. getShipName(targetId))
              else
                debugTrace("debug", " Failed to create order " .. tostring(order.order) .. " on target " .. getShipName(targetId))
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
  debugTrace("debug", " Commander " .. getShipName(sourceId) .. " has " .. tostring(#subordinatesList) .. " subordinates")
  for j = 1, #subordinatesList do
    local subordinate = subordinatesList[j]
    local subordinateId = toUniverseId(subordinatesList[j])
    local group = GetComponentData(subordinate, "subordinategroup")
    local assignment = ffi.string(C.GetSubordinateGroupAssignment(sourceId, group))
    debugTrace("debug",
      " Subordinate " .. getShipName(subordinateId) .. " is assigned to group " .. tostring(group) .. " with assignment " .. tostring(assignment))
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
      debugTrace("debug", "Clearing repeat orders on target " .. getShipName(targetId))
      if not C.RemoveAllOrders(targetId) then
        debugTrace("debug", "failed to clear target order queue for " .. getShipName(targetId))
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
  debugTrace("debug", "Refreshing repeat orders for " .. tostring(#commanders) .. " commanders, checkSubordinates=" .. tostring(checkSubordinates))
  for i = 1, #commanders do
    MimicRepeatOrders.cloneOrdersReset()
    local commanderId = toUniverseId(commanders[i])
    if (commanderId ~= nil) then
      MimicRepeatOrders.sourceId = commanderId
      local valid, errorData = MimicRepeatOrders.ValidateSourceShipAndCleanupOrders()
      local subordinatesCount = MimicRepeatOrders.countSubordinates()
      debugTrace("debug",
        " Refreshing commander " ..
        getShipName(commanderId) ..
        " validity: " .. tostring(valid) .. ", error: " .. tostring(errorData and errorData.info) .. ", subordinates: " .. tostring(subordinatesCount))
      if valid and subordinatesCount > 0 then
        local subordinates = {}
        local commanderOrders = MimicRepeatOrders.getRepeatOrders(commanderId)
        if MimicRepeatOrders.repeatOrdersCommanders[commanderId] == nil then
          debugTrace("debug", " Commander " .. getShipName(commanderId) .. " caching repeat orders for the first time")
          repeatOrdersCommanders[commanderId] = commanderOrders
          if #commanderOrders > 0 then
            for j = 1, #commanderOrders do
              local order = repeatOrdersCommanders[commanderId][j]
              debugTrace("debug",
                " Commander " .. getShipName(commanderId) .. " has repeat order " .. tostring(order.order) .. " at index " .. tostring(order.idx))
              order.params = GetOrderParams(commanderId, order.idx)
            end
            subordinates = MimicRepeatOrders.GetSubordinates()
          end
        else
          debugTrace("debug", " Commander " .. getShipName(commanderId) .. " repeat orders already cached")
          if MimicRepeatOrders.isOrdersEqual(commanderOrders, nil, MimicRepeatOrders.repeatOrdersCommanders[commanderId], true) then
            debugTrace("debug", " Commander " .. getShipName(commanderId) .. " orders unchanged")
            if (checkSubordinates) then
              subordinates = MimicRepeatOrders.GetSubordinates()
            end
            repeatOrdersCommanders[commanderId] = MimicRepeatOrders.repeatOrdersCommanders[commanderId]
          else
            debugTrace("debug", " Commander " .. getShipName(commanderId) .. " orders changed, updating cache and subordinates")
            repeatOrdersCommanders[commanderId] = commanderOrders
            for j = 1, #commanderOrders do
              local order = repeatOrdersCommanders[commanderId][j]
              debugTrace("debug",
                " Commander " .. getShipName(commanderId) .. " has repeat order " .. tostring(order.order) .. " at index " .. tostring(order.idx))
              order.params = GetOrderParams(commanderId, order.idx)
            end
            subordinates = MimicRepeatOrders.GetSubordinates()
          end
        end
        if #subordinates > 0 then
          debugTrace("debug", " Commander " .. getShipName(commanderId) .. " has " .. tostring(#subordinates) .. " subordinates to check")
          MimicRepeatOrders.targetIds = {}
          local transportTypes = MimicRepeatOrders.collectSourceWaresTransportTypes(commanderOrders)
          for j = 1, #subordinates do
            local valid, errorData = MimicRepeatOrders.isValidTargetShip(subordinates[j], transportTypes)
            if not valid then
              debugTrace("debug", "  Subordinate " .. getShipName(subordinates[j]) .. " is invalid, removing from list")
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
          debugTrace("debug", " Commander " .. getShipName(commanderId) .. " is invalid, skipping " .. tostring(subordinatesCount) .. " subordinates")
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

  debugTrace("debug", "Adding order " .. tostring(order) .. " to ship " .. getShipName(shipId))

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
    debugTrace("trace", " Param " .. tostring(key) .. " value: '" .. tostring(params[key]) .. "'")
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
            debugTrace("trace",
              " Setting order param[" ..
              tostring(orderParamDef.idx) .. "] " .. tostring(name) .. " to value: '" .. tostring(value[k]) .. "' as part of listOfString")
            SetOrderParam(shipId, newOrderIdx, orderParamDef.idx, nil, value[k])
          end
        else
          debugTrace("trace", " Setting order param[" .. tostring(orderParamDef.idx) .. "] " .. tostring(name) .. " to value: '" .. tostring(value) .. "'")
          SetOrderParam(shipId, newOrderIdx, orderParamDef.idx, nil, value)
        end
      end
    end
    C.EnableOrder(shipId, newOrderIdx)
    debugTrace("debug", " Successfully created order " .. tostring(order) .. " on target " .. getShipName(shipId))
  else
    debugTrace("debug", " Failed to create order " .. tostring(order) .. " on target " .. getShipName(shipId))
  end
end

function MimicRepeatOrders.ProcessRequest(_, _)
  if not MimicRepeatOrders.getArgs() then
    debugTrace("debug", "ProcessRequest invoked without args or invalid args")
    MimicRepeatOrders.reportError({ info = "missing_args" })
    return
  end
  debugTrace("debug", "ProcessRequest received command: " .. tostring(MimicRepeatOrders.args.command))
  if MimicRepeatOrders.args.command == "clone_orders" then
    local valid, errorData = MimicRepeatOrders.cloneOrdersPrepare()
    debugTrace("debug", " cloneOrdersPrepare returned valid=" .. tostring(valid) .. ", error=" .. tostring(errorData and errorData.info))
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
    debugTrace("debug", "ProcessRequest received unknown command: " .. tostring(MimicRepeatOrders.args.command))
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
      debugTrace("debug", "Order definition " .. orderDef .. " resolved to name " .. MimicRepeatOrders.validOrders[orderDef].name)
    else
      debugTrace("debug", "Order definition " .. orderDef .. " could not be resolved")
    end
  end
end

function MimicRepeatOrders.Init()
  getPlayerId()
  ---@diagnostic disable-next-line: undefined-global
  RegisterEvent("MimicRepeatOrders.Request", MimicRepeatOrders.ProcessRequest)
  MimicRepeatOrders.mapMenu = Lib.Get_Egosoft_Menu("MapMenu")
  debugTrace("debug", "MapMenu is " .. tostring(MimicRepeatOrders.mapMenu))
  MimicRepeatOrders.OrderNamesCollect()
  MimicRepeatOrders.loopOrdersSkillLimit = C.GetOrderLoopSkillLimit() * 3
  SetNPCBlackboard(MimicRepeatOrders.playerId, "$MimicRepeatOrdersLoopOrdersSkillLimit", MimicRepeatOrders.loopOrdersSkillLimit)
  AddUITriggeredEvent("MimicRepeatOrders", "Reloaded")
end

Register_Require_With_Init("extensions.mimic_repeat_orders.ui.mimic_repeat_orders", MimicRepeatOrders, MimicRepeatOrders.Init)

return MimicRepeatOrders
