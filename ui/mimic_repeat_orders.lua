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
    SingleBuy  = "",
    SingleSell = "",
  },
  sourceId = 0,
  loopOrdersSkillLimit = 0,
  targetIds = {},
  repeatOrdersCommanders = {},
}


local Lib = require("extensions.sn_mod_support_apis.ui.Library")

local debugTraceLevel =  "debug"

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
    debugTrace("debug","updating player_id to " .. tostring(converted))
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

local function copyAndEnrichTable(src, extraInfo)
  local dest = {}
  for k, v in pairs(src) do
    dest[k] = v
  end
  for k, v in pairs(extraInfo) do
    dest[k] = v
  end
  return dest
end

local function getShipName(shipId)
  if shipId == 0 then
    return "Unknown"
  end
  local name = GetComponentData(ConvertStringToLuaID(tostring(shipId)), "name")
  local idCode = ffi.string(C.GetObjectIDCode(shipId))
  return string.format("%s (%s)", name, idCode)
end

local function isTopCommander(shipId)
  local shipId = toUniverseId(shipId)
  local n = C.GetNumAllCommanders(shipId, 0)
  return n > 0
end

local function centerFrameVertically(frame)
  frame.properties.height = frame:getUsedHeight() + Helper.borderSize
  if (frame.properties.height > Helper.viewHeight ) then
    frame.properties.y = Helper.borderSize
    frame.properties.height = Helper.viewHeight - 2 * Helper.borderSize
  else
    frame.properties.y = (Helper.viewHeight - frame.properties.height) / 2
  end
end

function MimicRepeatOrders.recordResult()
  local data = MimicRepeatOrders.args or {}
  debugTrace("debug","recordResult called for command ".. tostring(data and data.command) .. " with result " .. tostring(data and data.result))
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
  local count = tonumber(C.GetOrders(buf, numOrders, shipId)) or 0
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

function MimicRepeatOrders.checkShip(shipId)
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
  if MimicRepeatOrders.getCargoCapacity(shipId) == 0 then
    return false, { info = "NoCargoCapacity" }
  end
  return true
end

function MimicRepeatOrders.getCargoCapacity(shipId)
  local menu = MimicRepeatOrders.mapMenu
  local shipId = toUniverseId(shipId)
  local numStorages = C.GetNumCargoTransportTypes(shipId, true)
  local buf = ffi.new("StorageInfo[?]", numStorages)
  local count = C.GetCargoTransportTypes(buf, numStorages, shipId, true, false)
  local capacity = 0
  for i = 0, count - 1 do
    local tags = menu.getTransportTagsFromString(ffi.string(buf[i].transport))
    if tags.container == true then
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
  for i=1, #orders do
    if MimicRepeatOrders.validOrders[orders[i].order] == nil then
      ordersToRemove[#ordersToRemove + 1] = orders[i]
    else
      if validOrders[orders[i].order] ~= true then
        validOrders[orders[i].order] = true
        validOrdersCount = validOrdersCount + 1
      end
    end
  end
  debugTrace("debug","Source ship " .. getShipName(sourceId) .. " has " .. tostring(validOrdersCount) .. " valid repeat orders and " .. tostring(#ordersToRemove) .. " invalid repeat orders to remove from a total of " .. tostring(#orders) .. " repeat orders")
  if (validOrdersCount < 2) then
    return false, { info = "NoEnoughValidRepeatOrders"}
  end
  if #ordersToRemove > 0 then
    debugTrace("debug","Source ship " .. getShipName(sourceId) .. " has " .. tostring(#ordersToRemove) .. " invalid repeat orders to remove")
    for i = #ordersToRemove, 1, -1 do
      local order = ordersToRemove[i]
      debugTrace("trace"," Removing invalid repeat order " .. tostring(order.order) .. " at index " .. tostring(order.idx))
      C.RemoveOrder(sourceId, order.idx, true, false)
    end
  end
  return true
end

function MimicRepeatOrders.isValidTargetShip(target)
  local targetId = toUniverseId(target)
  local valid, errorData = MimicRepeatOrders.checkShip(targetId)
  if not valid then
    return false, errorData
  end
  local loopSkill = MimicRepeatOrders.loopOrdersSkillLimit;
  local aiPilot = GetComponentData(ConvertStringToLuaID(tostring(targetId)), "assignedaipilot")
	local aiPilotSkill = aiPilot and math.floor(C.GetEntityCombinedSkill(ConvertIDTo64Bit(aiPilot), nil, "aipilot") * 15 / 100) or -1
  debugTrace("trace","Target ship " .. getShipName(targetId) .. " has AI pilot skill " .. tostring(aiPilotSkill) .. ", required is " .. tostring(loopSkill))
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
    debugTrace("debug","getArgs unable to resolve player id")
  else
    local list = GetNPCBlackboard(MimicRepeatOrders.playerId, "$MimicRepeatOrdersRequest")
    if type(list) == "table" and #list > 0 then
      debugTrace("debug","getArgs retrieved " .. tostring(#list) .. " entries from blackboard")
      for i = 1, #list do
        debugTrace("trace"," getArgs entry " .. tostring(i) .. ": " .. tostring(list[i]))
        MimicRepeatOrders.queueArgs[#MimicRepeatOrders.queueArgs + 1] = list[i]
      end
      SetNPCBlackboard(MimicRepeatOrders.playerId, "$MimicRepeatOrdersRequest", nil)
    elseif list ~= nil then
      debugTrace("debug","getArgs received non-table payload of type " .. type(list))
    else
      debugTrace("debug","getArgs found no blackboard entries for player " .. tostring(MimicRepeatOrders.playerId))
    end
  end
  if #MimicRepeatOrders.queueArgs > 0 then
    MimicRepeatOrders.args = MimicRepeatOrders.queueArgs[1]
    table.remove(MimicRepeatOrders.queueArgs, 1)
    debugTrace("debug","getArgs processing command ".. tostring(MimicRepeatOrders.args and MimicRepeatOrders.args.command) .. " with " .. tostring(#MimicRepeatOrders.queueArgs) .. " remaining in queue")
    return true
  end
  return false
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
  for i = 1, #targets do
    local targetId = toUniverseId(targets[i])
    local valid, errorData = MimicRepeatOrders.isValidTargetShip(targetId)
    if valid then
      targetIds[#targetIds + 1] = targetId
    else
      debugTrace("debug","Target ship " .. getShipName(targetId) .. " is invalid: " .. tostring(errorData and errorData.info))
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

function MimicRepeatOrders.isOrdersEqual(sourceOrders, sourceCargoCapacity, targetId, targetCargoCapacity, targetOrders)

  if targetId ~= nil then
    if MimicRepeatOrders.isLoopEnabled(targetId) == false then
      return false
    end
    targetOrders = MimicRepeatOrders.getRepeatOrders(targetId)
  end
  debugTrace("debug","Comparing " .. tostring(#sourceOrders) .. " source orders to " .. tostring(#targetOrders) .. " target orders with targetId " .. tostring(targetId))
  if #sourceOrders ~= #targetOrders then
    return false
  end
  for i = 1, #sourceOrders do
    local sourceOrder = sourceOrders[i]
    local targetOrder = targetOrders[i]
    debugTrace("trace"," Comparing source order " .. tostring(i) .. ": " .. tostring(sourceOrder.order) .. " to target order " .. tostring(i) .. ": " .. tostring(targetOrder.order))
    if sourceOrder.order ~= targetOrder.order then
      return false
    end
    local sourceParams = GetOrderParams(MimicRepeatOrders.sourceId, sourceOrder.idx)
    local targetParams = targetOrder.params or GetOrderParams(targetId, targetOrder.idx)
    local sourceWare = sourceParams[1].value
    local targetWare = targetParams[1].value
    debugTrace("trace","  Comparing source ware " .. tostring(sourceWare) .. " to target ware " .. tostring(targetWare))
    if sourceWare ~= targetWare then
      return false
    end
    local sourceAmount = (sourceCargoCapacity > 0) and sourceParams[5].value or 0
    local targetAmount = (targetCargoCapacity > 0) and (targetParams[5].value * sourceCargoCapacity / targetCargoCapacity) or 0
    debugTrace("trace","  Comparing source amount " .. tostring(sourceAmount) .. " to target amount " .. tostring(targetAmount))
    if math.abs(sourceAmount - targetAmount) > 0.01 then
      return false
    end
    local sourcePrice = sourceParams[7].value * 100
    local targetPrice = targetParams[7].value * 100
    debugTrace("trace","  Comparing source price " .. tostring(sourcePrice) .. " to target price " .. tostring(targetPrice))
    if sourcePrice ~= targetPrice then
      return false
    end
    local sourceLocations = sourceParams[4].value or {}
    local targetLocations = targetParams[4].value or {}
    debugTrace("trace","  Comparing source locations " .. tostring(#sourceLocations) .. " to target locations " .. tostring(#targetLocations))
    if #sourceLocations ~= #targetLocations then
      return false
    end
    for j = 1, #sourceLocations do
      debugTrace("trace","   Comparing source location " .. tostring(sourceLocations[j]) .. " to target location " .. tostring(targetLocations[j]) .. " = " .. tostring(tostring(sourceLocations[j]) == tostring(targetLocations[j])))
      if tostring(sourceLocations[j]) ~= tostring(targetLocations[j]) then
        return false
      end
    end
  end
  return true
end

function MimicRepeatOrders.cloneOrdersExecute(skipResult)
  debugTrace("debug","Executing clone orders from source " .. getShipName(MimicRepeatOrders.sourceId) .. " to " .. tostring(#MimicRepeatOrders.targetIds) .. " targets")
  local sourceOrders = MimicRepeatOrders.getRepeatOrders(MimicRepeatOrders.sourceId)
  local targets = MimicRepeatOrders.targetIds
  local sourceCargoCapacity = MimicRepeatOrders.getCargoCapacity(MimicRepeatOrders.sourceId)
  local processedOrders = 0
  for i = 1, #targets do
    local targetId = targets[i]
    debugTrace("debug","Cloning orders to target " .. getShipName(targetId))
    local targetCargoCapacity = MimicRepeatOrders.getCargoCapacity(targetId)
    if MimicRepeatOrders.isOrdersEqual(sourceOrders, sourceCargoCapacity, targetId, targetCargoCapacity) then
      debugTrace("debug","Target orders on " .. getShipName(targetId) .. " already match source orders, skipping")
      processedOrders = processedOrders + #sourceOrders
    else
      if not C.RemoveAllOrders(targetId) then
        debugTrace("debug","failed to clear target order queue for " .. getShipName(targetId))
      else
        C.CreateOrder(targetId, "Wait", true)
        C.EnablePlannedDefaultOrder(targetId, false)
        C.SetOrderLoop(targetId, 0, false)
        for j = 1, #sourceOrders do
          local order = sourceOrders[j]
          if order.ware == nil then
            local orderParams = GetOrderParams(MimicRepeatOrders.sourceId, order.idx)
            order.ware = orderParams[1].value
            order.amount = (sourceCargoCapacity > 0) and (orderParams[5].value / sourceCargoCapacity ) or 0
            order.price = orderParams[7].value * 100
            order.locations = orderParams[4].value
          end
          local newOrderIdx = C.CreateOrder(targetId, order.order, false)
          if newOrderIdx and newOrderIdx > 0 then
            SetOrderParam(targetId, newOrderIdx, 1, nil, order.ware)
            SetOrderParam(targetId, newOrderIdx, 5, nil, math.floor(order.amount * targetCargoCapacity + 0.5))
            SetOrderParam(targetId, newOrderIdx, 7, nil, order.price)
            local locations = order.locations or {}
            for j = 1, #locations do
              SetOrderParam(targetId, newOrderIdx, 4, nil, locations[j])
            end
            debugTrace("debug"," Created order " .. tostring(order.order) .. " on target " .. getShipName(targetId) .. " at index " .. tostring(newOrderIdx))
            C.EnableOrder(targetId, newOrderIdx)
            processedOrders = processedOrders + 1
          else
            debugTrace("debug"," Failed to create order " .. tostring(order.order) .. " on target " .. getShipName(targetId))
          end
        end
      end
    end
  end
  MimicRepeatOrders.cloneOrdersReset()

  if skipResult == nil  or skipResult == false then
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
  debugTrace("debug"," Commander " .. getShipName(sourceId) .. " has " .. tostring(#subordinatesList) .. " subordinates")
  for j = 1, #subordinatesList do
    local subordinate = subordinatesList[j]
    local subordinateId = toUniverseId(subordinatesList[j])
    local group = GetComponentData(subordinate, "subordinategroup")
    local assignment = ffi.string(C.GetSubordinateGroupAssignment(sourceId, group))
    debugTrace("debug"," Subordinate " .. getShipName(subordinateId) .. " is assigned to group " .. tostring(group) .. " with assignment " .. tostring(assignment))
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
      debugTrace("debug","Clearing repeat orders on target " .. getShipName(targetId))
      if not C.RemoveAllOrders(targetId) then
        debugTrace("debug","failed to clear target order queue for " .. getShipName(targetId))
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
  if skipResult == nil  or skipResult == false then
    MimicRepeatOrders.reportSuccess({ info = "OrdersCleared", details = string.format("%d targets cleared", #MimicRepeatOrders.targetIds) })
  end
end

function MimicRepeatOrders.repeatOrdersCommandersRefresh()
  local commanders =  MimicRepeatOrders.args.list or {}
  local checkSubordinates = MimicRepeatOrders.args.checkSubordinates == 1
  local repeatOrdersCommanders = {}
  debugTrace("debug","Refreshing repeat orders for " .. tostring(#commanders) .. " commanders, checkSubordinates=" .. tostring(checkSubordinates))
  for i = 1, #commanders do
    MimicRepeatOrders.cloneOrdersReset()
    local commanderId = toUniverseId(commanders[i])
    if (commanderId ~= nil) then
      MimicRepeatOrders.sourceId = commanderId
      local valid, errorData = MimicRepeatOrders.ValidateSourceShipAndCleanupOrders()
      local subordinatesCount = MimicRepeatOrders.countSubordinates()
      debugTrace("debug"," Refreshing commander " .. getShipName(commanderId) .. " validity: " .. tostring(valid) .. ", error: " .. tostring(errorData and errorData.info) .. ", subordinates: " .. tostring(subordinatesCount))
      if valid and subordinatesCount > 0 then
        local subordinates = {}
        local commanderOrders = MimicRepeatOrders.getRepeatOrders(commanderId)
        if MimicRepeatOrders.repeatOrdersCommanders[commanderId]  ==  nil then
          debugTrace("debug"," Commander " .. getShipName(commanderId) .. " caching repeat orders for the first time")
          repeatOrdersCommanders[commanderId] = commanderOrders
          if #commanderOrders > 0 then
            for j = 1, #commanderOrders do
              local order = repeatOrdersCommanders[commanderId][j]
              debugTrace("debug"," Commander " .. getShipName(commanderId) .. " has repeat order " .. tostring(order.order) .. " at index " .. tostring(order.idx))
              order.params = GetOrderParams(commanderId, order.idx)
            end
            subordinates = MimicRepeatOrders.GetSubordinates()
          end
        else
          debugTrace("debug"," Commander " .. getShipName(commanderId) .. " repeat orders already cached")
          local cargoCapacity = MimicRepeatOrders.getCargoCapacity(commanderId)
          if MimicRepeatOrders.isOrdersEqual(commanderOrders, cargoCapacity, nil, cargoCapacity, MimicRepeatOrders.repeatOrdersCommanders[commanderId]) then

            debugTrace("debug"," Commander " .. getShipName(commanderId) .. " orders unchanged")
            if (checkSubordinates) then
              subordinates = MimicRepeatOrders.GetSubordinates()
            end
            repeatOrdersCommanders[commanderId] = MimicRepeatOrders.repeatOrdersCommanders[commanderId]
          else
            debugTrace("debug"," Commander " .. getShipName(commanderId) .. " orders changed, updating cache and subordinates")
            repeatOrdersCommanders[commanderId] = commanderOrders
            for j = 1, #commanderOrders do
              local order = repeatOrdersCommanders[commanderId][j]
              debugTrace("debug"," Commander " .. getShipName(commanderId) .. " has repeat order " .. tostring(order.order) .. " at index " .. tostring(order.idx))
              order.params = GetOrderParams(commanderId, order.idx)
            end
            subordinates = MimicRepeatOrders.GetSubordinates()
          end
        end
        if #subordinates > 0 then
          debugTrace("debug"," Commander " .. getShipName(commanderId) .. " has " .. tostring(#subordinates) .. " subordinates to check")
          MimicRepeatOrders.targetIds = {}
          for j = 1, #subordinates do
            local valid, errorData = MimicRepeatOrders.isValidTargetShip(subordinates[j])
            if not valid then
              debugTrace("debug","  Subordinate " .. getShipName(subordinates[j]) .. " is invalid, removing from list")
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
          debugTrace("debug"," Commander " .. getShipName(commanderId) .. " is invalid, skipping " .. tostring(subordinatesCount) .. " subordinates")
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

function MimicRepeatOrders.ProcessRequest(_, _)
  if not MimicRepeatOrders.getArgs() then
    debugTrace("debug","ProcessRequest invoked without args or invalid args")
    MimicRepeatOrders.reportError({info ="missing_args"})
    return
  end
  debugTrace("debug","ProcessRequest received command: " .. tostring(MimicRepeatOrders.args.command))
  if MimicRepeatOrders.args.command == "clone_orders" then
    local valid, errorData = MimicRepeatOrders.cloneOrdersPrepare()
    debugTrace("debug"," cloneOrdersPrepare returned valid=" .. tostring(valid) .. ", error=" .. tostring(errorData and errorData.info))
    if valid then
      MimicRepeatOrders.cloneOrdersExecute()
    else
      MimicRepeatOrders.reportError(errorData)
    end
  elseif MimicRepeatOrders.args.command == "refresh_commanders" then
    MimicRepeatOrders.repeatOrdersCommandersRefresh()
  elseif MimicRepeatOrders.args.command == "clear_orders" then
    MimicRepeatOrders.clearRepeatOrders(false, false)
  else
    debugTrace("debug","ProcessRequest received unknown command: " .. tostring(MimicRepeatOrders.args.command))
    MimicRepeatOrders.reportError({ info = "UnknownCommand" })
  end
end

function MimicRepeatOrders.OrderNamesCollect()
  for orderDef, _ in pairs(MimicRepeatOrders.validOrders) do
    local buf = ffi.new("OrderDefinition")
    local found = C.GetOrderDefinition(buf, orderDef)
    if found then
      local orderName = ffi.string(buf.name)
      MimicRepeatOrders.validOrders[orderDef] = orderName
      debugTrace("debug","Order definition " .. orderDef .. " resolved to name " .. MimicRepeatOrders.validOrders[orderDef])
    else
      debugTrace("debug","Order definition " .. orderDef .. " could not be resolved")
    end
  end
end

function MimicRepeatOrders.Init()
  getPlayerId()
  ---@diagnostic disable-next-line: undefined-global
  RegisterEvent("MimicRepeatOrders.Request", MimicRepeatOrders.ProcessRequest)
  MimicRepeatOrders.mapMenu = Lib.Get_Egosoft_Menu("MapMenu")
  debugTrace("debug","MapMenu is " .. tostring(MimicRepeatOrders.mapMenu))
  MimicRepeatOrders.OrderNamesCollect()
  MimicRepeatOrders.loopOrdersSkillLimit = C.GetOrderLoopSkillLimit() * 3
  SetNPCBlackboard(MimicRepeatOrders.playerId, "$MimicRepeatOrdersLoopOrdersSkillLimit", MimicRepeatOrders.loopOrdersSkillLimit)
  AddUITriggeredEvent("MimicRepeatOrders", "Reloaded")
end

Register_Require_With_Init("extensions.mimic_repeat_orders.ui.mimic_repeat_orders", MimicRepeatOrders, MimicRepeatOrders.Init)

return MimicRepeatOrders
