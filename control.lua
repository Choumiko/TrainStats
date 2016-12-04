local Event = require 'stdlib.event.event'
local Trains = require 'Trains'
local GUI = require 'stdlib.gui.gui'

local math = math
MOD_NAME = "TrainStats"
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
  global.player = global.player or {}
  global.guiSettings = global.guiSettings or {}
end

local function initPlayer(player)
  global.guiSettings[player.index] = global.guiSettings[player.index] or {}
  local settings = global.guiSettings[player.index]
  settings.displayedStats = settings.displayedStats or "travelTimes"
end

local function initPlayers()
  for _, p in pairs(game.players) do
    initPlayer(p)
  end
end

local function on_player_created(event)
  initPlayer(game.players[event.player_index])
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
    initPlayers()
    for _, trainData in pairs(global._trains) do
      trainData.guis = trainData.guis or {}
    end
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
  return true
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
    updateStatistics(signalTimes,time, data)
    return true
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

    return true
  end
end

trainState[defines.train_state.stop_for_auto_control] = function(data, tick)
  if data.previousState == defines.train_state.wait_station then
    return trainState[defines.train_state.on_the_path](data, tick)
  end
end

GUI.destroy = function(player)
  if player.gui.left.trainStats and player.gui.left.trainStats.valid then
    player.gui.left.trainStats.destroy()
    return
  end
end

GUI.button = function(args)
  args.type = "button"
  if not args.style then
    args.style = "trainStats_button"
  end
  return args
end

GUI.label = function(args)
  args.type = "label"
  if not args.style then
    args.style = "trainStats_label"
  end
  return args
end

GUI.create = function(player)
  local train = player.vehicle.train
  local data = Trains.getData(train)
  local records = data.train.schedule.records
  if not records then return end
  local mainFrame = player.gui.left.add{type = "frame", name = "trainStats", caption = "Statistics for train #" .. data.id,
    direction = "vertical"}
    mainFrame.add(GUI.label{caption=Trains.getType(train)})
  local buttonFlow = mainFrame.add{type = "flow", name = "trainstats_buttonFlow", direction = "horizontal"}
  local inboundFrame = mainFrame.add{type = "frame", name = "trainstats_frame1"}
  buttonFlow.add(GUI.button({caption = "Time", name = "trainstats_tgl_time"}))
  buttonFlow.add(GUI.button({caption = "Waiting", name = "trainstats_tgl_waiting"}))
  buttonFlow.add(GUI.button({caption = "Signals", name = "trainstats_tgl_signals"}))
  --buttonFlow.add{type = "button", caption = "Time", name = "trainstats_tgl_time"}
  local pane = inboundFrame.add{
    type = "scroll-pane",
  }
  pane.style.maximal_height = math.ceil(40*5)
  pane.horizontal_scroll_policy = "never"
  pane.vertical_scroll_policy = "auto"
  local statsTable = pane.add{type = "table", name = "trainstats_table", colspan = 7, style = "trainStats_table"}
  --statsTable.style.cell_spacing = 7
  statsTable.add(GUI.label({caption = "From"}))
  statsTable.add(GUI.label({caption = ""}))
  statsTable.add(GUI.label({caption = "To"}))
  statsTable.add(GUI.label({caption = "min"}))
  statsTable.add(GUI.label({caption = "max"}))
  statsTable.add(GUI.label({caption = "avg"}))
  statsTable.add(GUI.label({caption = "last", tooltip = "asdf"}))
  local guiSetting = global.guiSettings[player.index].displayedStats
  local statsToDisplay = data[guiSetting]
  local displayed = {}
  for i = 1, #records do
    local fromStation = tostring(records[i].station)
    displayed[fromStation] = displayed[fromStation] or {}
    local next = (i % #records) + 1
    local toStation = tostring(records[next].station)
    if not displayed[fromStation][toStation] and statsToDisplay[fromStation] and (statsToDisplay[fromStation][toStation] or guiSetting == "waitingTimes" ) then
      local stats = guiSetting == "waitingTimes" and statsToDisplay[fromStation] or statsToDisplay[fromStation][toStation]
      toStation = guiSetting == "waitingTimes" and "" or toStation
      statsTable.add(GUI.label({caption = fromStation}))
      statsTable.add(GUI.label({caption = " "}))
      statsTable.add(GUI.label({caption = toStation}))
      statsTable.add(GUI.label({caption = round(stats.min/60, 1)}))
      statsTable.add(GUI.label({caption = round(stats.max/60, 1)}))
      statsTable.add(GUI.label({caption = round(stats.avg/60, 1)}))
      local last = stats.sets[stats.index] and stats.sets[stats.index] or 0
      statsTable.add(GUI.label({caption = round(last/60, 1)}))
    end
    displayed[fromStation][toStation] = true
  end
  return mainFrame
end

GUI.changeDisplay = function(player_index, displayedStats)
  local player = game.players[player_index]
  global.guiSettings[player_index].displayedStats = displayedStats
  if player.gui.left.trainStats then
    GUI.destroy(player)
    if global.player[player.index] then
      local trainData = Trains.getData(global.player[player.index].train)
      trainData.guis[player.index] = GUI.create(player)
    end
  end
end

GUI.displayTravelTime = function(event)
  GUI.changeDisplay(event.player_index, "travelTimes")
end

GUI.displayWaitingTime = function(event)
  GUI.changeDisplay(event.player_index, "waitingTimes")
end

GUI.displaySignalTimes = function(event)
  GUI.changeDisplay(event.player_index, "signalTimes")
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
  if trainState[train.state](data, event.tick) then
    for player_index, gui in pairs(data.guis) do
      if gui.valid then
        GUI.destroy(game.players[player_index])
        data.guis[player_index] = GUI.create(game.players[player_index])
      else
        data.guis[player_index] = nil
      end
    end
  end
  --log(serpent.line(data,{comment=false}))
end

local function on_player_driving_changed_state(event)
  local player = game.players[event.player_index]
  if player.vehicle and (player.vehicle.type == "locomotive" or player.vehicle.type == "cargo-wagon") then
    global.player[player.index] = player.vehicle
    local trainInfo = Trains.getData(player.vehicle.train)
    if trainInfo then
      trainInfo.guis[player.index] = GUI.create(player)
    end
  end
  if not player.vehicle and global.player[player.index] then
    GUI.destroy(player)
    local vehicle = global.player[player.index]
    if vehicle.valid and (vehicle.type == "locomotive" or vehicle.type == "cargo-wagon") then
      local trainInfo = Trains.getData(global.player[player.index].train)
      if trainInfo then
        trainInfo.guis[player.index] = nil
      end
    end
    global.player[player.index] = nil
  end
end

Event.register(defines.events.on_built_entity, Trains._on_rolling_stock_built)
Event.register(defines.events.on_entity_died, Trains._on_rolling_stock_removed)
Event.register(defines.events.on_preplayer_mined_item, Trains._on_rolling_stock_removed)
Event.register(defines.events.on_tick, Trains.on_tick)
Event.register(defines.events.on_train_changed_state, on_train_changed_state)
Event.register(defines.events.on_player_driving_changed_state, on_player_driving_changed_state)

GUI.on_click('trainstats_tgl_time', GUI.displayTravelTime)
GUI.on_click('trainstats_tgl_waiting', GUI.displayWaitingTime)
GUI.on_click('trainstats_tgl_signals', GUI.displaySignalTimes)

script.on_init(onInit)
script.on_load(onLoad)
script.on_configuration_changed(onConfigurationChanged)
script.on_event(defines.events.on_player_created, on_player_created)

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

end
--/c remote.call("trainstats", "saveVar")
interface.saveVar = function(var, name, varname)
  local n = name or ""
  game.write_file("trainStats"..n..".lua", serpent.block(var or global, {name=varname or "global", comment=false}))
end

remote.add_interface("trainstats", interface)


