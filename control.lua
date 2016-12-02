local Event = require 'stdlib.event.event'
local Trains = require 'Trains'
local math = math
MOD_NAME = "TrainStatistics"

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
  data.travelTimes[fromStation][toStation] = data.travelTimes[fromStation][toStation] or {avg = 0, min= math.huge, max = 0, count = 0}
  local travelTimes = data.travelTimes[fromStation][toStation]
  local timeBetween = tick - data.previous.left
  if timeBetween < travelTimes.min then travelTimes.min = timeBetween end
  if timeBetween > travelTimes.max then travelTimes.max = timeBetween end
  local c = travelTimes.count
  travelTimes.avg = (travelTimes.avg * c + timeBetween) / (c + 1)
  travelTimes.count = c + 1
  data.previous = {station = toStation, arrived = tick, left = 0}

  local signalTimes = data.signalTimes[fromStation] and data.signalTimes[fromStation][toStation]
  if signalTimes then
    c = signalTimes.count
    signalTimes.avg = (signalTimes.avg * c + signalTimes.current) / (c + 1)
    signalTimes.count = c + 1
    signalTimes.arrived = false
    signalTimes.current = 0
  end

  log(data.id .. ": " .. fromStation .. " -> " .. toStation .. " : " .. timeBetween/60 .. "s" )
  log("TT avg: " .. travelTimes.avg/60 .. " min: " .. travelTimes.min/60 .. " max: " .. travelTimes.max/60 .. " c: " .. travelTimes.count)
  if signalTimes then
    log("ST avg: " .. signalTimes.avg/60 .. " min: " .. signalTimes.min/60 .. " max: " .. signalTimes.max/60 .. " c: " .. signalTimes.count)
  end
end

trainState[defines.train_state.wait_signal] = function(data, tick)
  if not data.previous.station then
    return
  end
  log("wait signal")
  local fromStation = data.previous.station
  local toStation = tostring(data.train.schedule.records[data.train.schedule.current].station)
  data.signalTimes[fromStation] = data.signalTimes[fromStation] or {}
  data.signalTimes[fromStation][toStation] = data.signalTimes[fromStation][toStation] or {arrived = 0, current = 0, avg = 0, min= math.huge, max = 0, count = 0}
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
    local time = tick - data.signalTimes[fromStation][toStation].arrived
    if time < signalTimes.min then signalTimes.min = time end
    if time > signalTimes.max then signalTimes.max = time end
    signalTimes.current = signalTimes.current + time

    log(data.id .. ": " .. fromStation .. " -> " .. toStation .. " : " .. time/60 .. "s" )
    log("avg: " .. signalTimes.avg/60 .. " min: " .. signalTimes.min/60 .. " max: " .. signalTimes.max/60 .. " current: " .. signalTimes.current .. " c: " .. signalTimes.count)
    return
  end
  if data.previousState == defines.train_state.wait_station then
    if not data.previous.station then return end
    log("left station")
    global.stationStats[data.previous.station] = global.stationStats[data.previous.station] or {min = math.huge, max = 0, avg = 0, count = 0}
    local stationStats = global.stationStats[data.previous.station]
    local waitingTime = tick - data.previous.arrived
    data.previous.left = tick
    if waitingTime < stationStats.min then stationStats.min = waitingTime end
    if waitingTime > stationStats.max then stationStats.max = waitingTime end
    local c = stationStats.count
    stationStats.avg = (stationStats.avg * c + waitingTime) / (c + 1)
    stationStats.count = c + 1
    log("Station stats for " .. data.previous.station .. " min: " .. stationStats.min/60 .. " max: " .. stationStats.max/60 .. " avg: " .. stationStats.avg/60 .. " c: ".. stationStats.count)
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
local interface = {
  init = function()
    initGlobal()
    for id, data in pairs(global._trains) do
      data.id = id
      data.travelTimes = data.travelTimes or {}
      data.signalTimes = data.signalTimes or {}
      data.previous.left = data.previous.left or data.previous.arrived
    end
  end,

  reset = function()
    initGlobal()
    for from, toStation in pairs(global.stationStats) do
      for to, data in pairs(toStation) do
        data.min = math.huge
        data.max = 0
        data.avg = 0
        data.count = 0
      end
    end
    for id, trainData in pairs(global._trains) do
      trainData.previous.station = false
      for from, toStation in pairs(trainData.travelTimes) do
        for to, data in pairs(toStation) do
          data.min = math.huge
          data.max = 0
          data.avg = 0
          data.count = 0
        end
      end
      for from, toStation in pairs(trainData.signalTimes) do
        for to, data in pairs(toStation) do
          data.arrived = false
          data.current = 0
          data.min = math.huge
          data.max = 0
          data.avg = 0
          data.count = 0
        end
      end
    end
  end
}

remote.add_interface("trainstats", interface)


