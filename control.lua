local Event = require 'stdlib.event.event'
local Trains = require 'Trains'
local math = math
MOD_NAME = "TrainStatistics"
local ROLLING_AVERAGE_SIZE = 5


local function round(num, idp)
  local mult = 10 ^ (idp or 0)
  return math.floor(num * mult + 0.5) / mult
end

local function initGlobal()
  log("initGlobal")
  Trains.isSetup = true
  global._trains = global._trains or {}
  global.stationStats = global.stationStats or {}
end

local function onInit()
  --Trains.setup()
  log("on_init")
  initGlobal()
end

local function onLoad()

end

local function onConfigurationChanged(data)
  if not data or not data.mod_changes then
    return
  end
  --local newVersion
  --local oldVersion
  if data.mod_changes[MOD_NAME] then
    --newVersion = data.mod_changes[MOD_NAME].new_version
    --oldVersion = data.mod_changes[MOD_NAME].old_version
    log("config changed")
    initGlobal()
  end
end

local function updateStatistics(data, time)
  data.index = ((data.index or 0) % ROLLING_AVERAGE_SIZE) + 1
  data.sets[data.index] = time
  local sum = 0
  local min = data.sets[1]
  local max = data.sets[1]
  for _, t in pairs(data.sets) do
    sum = sum + t
    if t < min then min = t end
    if t > max then max = t end
  end
  data.min = min
  data.max = max
  data.avg = sum / #data.sets
end

local trainState = {}
trainState[defines.train_state.wait_station] = function(data, tick)
  log("wait station")
  if not data.previous.station then
    data.previous = {station = tostring(data.train.schedule.records[data.train.schedule.current].station), arrived = tick, left = 0}
    return
  end
  local fromStation = data.previous.station
  local toStation = tostring(data.train.schedule.records[data.train.schedule.current].station)
  data.travelTimes[fromStation] = data.travelTimes[fromStation] or {}
  data.travelTimes[fromStation][toStation] = data.travelTimes[fromStation][toStation] or {min= math.huge, max = 0, avg = 0, index = 0, sets = {}}
  local travelTimes = data.travelTimes[fromStation][toStation]
  local time = tick - data.previous.left
  updateStatistics(travelTimes,time)
  data.previous = {station = toStation, arrived = tick, left = 0}

  --[[
  local signalTimes = data.signalTimes[fromStation] and data.signalTimes[fromStation][toStation]
  if signalTimes then
    local c = signalTimes.count
    signalTimes.avg = (signalTimes.avg * c + signalTimes.current) / (c + 1)
    signalTimes.count = c + 1
    signalTimes.arrived = false
    signalTimes.current = 0
  end
]]--
end

trainState[defines.train_state.wait_signal] = function(data, tick)
  if not data.previous.station then
    return
  end
  log("wait signal")
  local fromStation = data.previous.station
  local toStation = tostring(data.train.schedule.records[data.train.schedule.current].station)
  data.signalTimes[fromStation] = data.signalTimes[fromStation] or {}
  data.signalTimes[fromStation][toStation] = data.signalTimes[fromStation][toStation] or {arrived = 0, min= math.huge, max = 0, avg = 0, index = 0, sets = {}}
  local signalTimes = data.signalTimes[fromStation][toStation]
  signalTimes.arrived = tick
end

trainState[defines.train_state.on_the_path] = function(data, tick)
  if data.previousState == defines.train_state.wait_signal then
    log("left signal")
    if not data.previous.station then
      return
    end
    local fromStation = data.previous.station
    local toStation = tostring(data.train.schedule.records[data.train.schedule.current].station)
    local signalTimes = data.signalTimes[fromStation][toStation]
    if not signalTimes or not signalTimes.arrived then return end
    local time = tick - signalTimes.arrived
    updateStatistics(signalTimes,time)
    return
  end
  if data.previousState == defines.train_state.wait_station then
    if not data.previous.station then return end
    log("left station")
    local station = data.previous.station
    global.stationStats[station] = global.stationStats[station] or {min = math.huge, max = 0, avg = 0, index = 0, sets = {}}
    local stationStats = global.stationStats[station]
    local time = tick - data.previous.arrived
    data.waitingTimes[station] = data.waitingTimes[station] or {min = math.huge, max = 0, avg = 0, index = 0, sets = {}}
    data.previous.left = tick

    updateStatistics(stationStats,time)
    updateStatistics(data.waitingTimes[station], time)

    return
  end
end

trainState[defines.train_state.stop_for_auto_control] = function(data, tick)
  if data.previousState == defines.train_state.wait_station then
    return trainState[defines.train_state.on_the_path](data, tick)
  end
end

local function on_train_changed_state(event)
  --log("train changed state " .. event.train.state)
  if not trainState[event.train.state] then return end
  local data = Trains.getData(event.train)
  local train = event.train
  local schedule = train.schedule
  data.previousState = data.currentState
  data.currentState = train.state
  if not schedule.records or #schedule.records < 1 then return end
  trainState[train.state](data, event.tick)
  --log(serpent.line(data,{comment=false}))
end

Event.register(defines.events.on_built_entity, Trains._on_rolling_stock_built)
Event.register(defines.events.on_entity_died, Trains._on_rolling_stock_removed)
Event.register(defines.events.on_preplayer_mined_item, Trains._on_rolling_stock_removed)
Event.register(defines.events.on_tick, Trains.on_tick)
Event.register(defines.events.on_train_changed_state, on_train_changed_state)

script.on_init(onInit)
script.on_load(onLoad)
script.on_configuration_changed(onConfigurationChanged)
-- /c remote.call("trainstats", "init")
local interface = {}
interface.init = function()
  initGlobal()
  for id, data in pairs(global._trains) do
    data.id = id
    data.travelTimes = data.travelTimes or {}
    data.signalTimes = data.signalTimes or {}
    data.waitingTimes = data.waitingTimes or {}
    data.previous.left = data.previous.left or data.previous.arrived
  end
end

interface.reset = function()
  --log(serpent.block(global.stationStats,{comment=false}))
  for _, data in pairs(global.stationStats) do
    data.min = math.huge
    data.max = 0
    data.avg = 0
    data.index = 0
    data.sets = {[1] = 0}
  end
  for _, trainData in pairs(global._trains) do
    trainData.previous.station = false
    trainData.travelTimes = {}
    trainData.signalTimes = {}
    trainData.waitingTimes = {}
  end
  interface.init()
end

interface.gui = function()
  if game.player.gui.left.trainStats then
    game.player.gui.left.trainStats.destroy()
    return
  end
  global.selected =  game.player.selected and game.player.selected.train or game.player.vehicle and game.player.vehicle.train
  local train = game.player.selected and game.player.selected.train or global.selected
  local data = Trains.getData(train)
  local records = data.train.schedule.records
  if not records then return end
  local mainFrame = game.player.gui.left.add{type = "frame", name = "trainStats", caption = "Statistics",
    direction = "vertical"}
  local buttonFlow = mainFrame.add{type = "flow", name = "trainstats_buttonFlow", direction = "horizontal"}
  local inboundFrame = mainFrame.add{type = "frame", name = "trainstats_frame1"}
  buttonFlow.add{type = "button", caption = "Time", name = "trainstats_tgl_time"}
  buttonFlow.add{type = "button", caption = "Waiting", name = "trainstats_tgl_waiting"}
  buttonFlow.add{type = "button", caption = "Signals", name = "trainstats_tgl_signals"}
  --buttonFlow.add{type = "button", caption = "Time", name = "trainstats_tgl_time"}
  local pane = inboundFrame.add{
    type = "scroll-pane",
  }
  pane.style.maximal_height = math.ceil(40*5)
  pane.horizontal_scroll_policy = "never"
  pane.vertical_scroll_policy = "auto"
  local statsTable = pane.add{type = "table", name = "trainstats_table", colspan = 7}
  statsTable.add{type = "label", caption = "From"}
  statsTable.add{type = "label", caption = ""}
  statsTable.add{type = "label", caption = "To"}
  statsTable.add{type = "label", caption = "min"}
  statsTable.add{type = "label", caption = "max"}
  statsTable.add{type = "label", caption = "avg"}
  statsTable.add{type = "label", caption = "last"}
  --[[
  statsTable.add{type = "label", caption = "waiting"}
  statsTable.add{type = "label", caption = ""}
  statsTable.add{type = "label", caption = "waiting"}
  statsTable.add{type = "label", caption = ""}
  statsTable.add{type = "label", caption = ""}
  statsTable.add{type = "label", caption = ""}
  statsTable.add{type = "label", caption = ""}
  ]]--
  for i = 1, #records do
    local fromStation = tostring(records[i].station)
    local next = (i % #records) + 1
    local toStation = tostring(records[next].station)
    if data.travelTimes[fromStation] and data.travelTimes[fromStation][toStation] then
      local stats = data.travelTimes[fromStation][toStation]
      statsTable.add{type = "label", caption = fromStation}
      statsTable.add{type = "label", caption = " "}
      statsTable.add{type = "label", caption = toStation}
      statsTable.add{type = "label", caption = round(stats.min/60, 1)}
      statsTable.add{type = "label", caption = round(stats.max/60, 1)}
      statsTable.add{type = "label", caption = round(stats.avg/60, 1)}
      statsTable.add{type = "label", caption = round(stats.sets[stats.index]/60, 1)}
    end
    --[[
    local stats = data.waitingTimes[fromStation]
    local caption = stats and round(stats.min/60, 1) .. " / " .. round(stats.max/60, 1) .. " / " ..round(stats.avg/60, 1) .. " / " .. round(stats.last/60, 1) or ""
    statsTable.add{type = "label", caption = caption}

    statsTable.add{type = "label", caption = ""}

    stats = stats and data.waitingTimes[toStation]
    caption = stats and round(stats.min/60, 1) .. " / " .. round(stats.max/60, 1) .. " / " ..round(stats.avg/60, 1) .. " / " .. round(stats.last/60, 1) or ""
    statsTable.add{type = "label", caption = caption}

    statsTable.add{type = "label", caption = ""}
    statsTable.add{type = "label", caption = ""}
    statsTable.add{type = "label", caption = ""}
    statsTable.add{type = "label", caption = ""}
]]--
  end
end
--/c remote.call("trainstats", "saveVar")
interface.saveVar = function(var, name, varname)
  local n = name or ""
  game.write_file("trainStats"..n..".lua", serpent.block(var or global, {name=varname or "global", comment=false}))
end

remote.add_interface("trainstats", interface)


