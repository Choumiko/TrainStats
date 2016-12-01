local Event = require 'stdlib.event.event'
local Trains = require 'Trains'
local math = math
MOD_NAME = "TrainStatistics"

local function initGlobal()
  log("initGlobal")
  Trains.isSetup = true
  global._trains = global._trains or {}
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

local trainState = {
  [defines.train_state.wait_station] = function(data, tick)
    if not data.previous.station then
      data.previous = {station = tostring(data.train.schedule.records[data.train.schedule.current].station), arrived = tick}
      return
    end
    local records = data.train.schedule.records
    local current = data.train.schedule.current
    local fromStation = data.previous.station
    local toStation = tostring(records[current].station)
    data.travelTimes[fromStation] = data.travelTimes[fromStation] or {[toStation] = {avg = 0, min= math.huge, max = 0, count = 0}}
    local travelTimes = data.travelTimes[fromStation][toStation]
    local timeBetween = tick - data.previous.arrived
    if timeBetween < travelTimes.min then travelTimes.min = timeBetween end
    if timeBetween > travelTimes.max then travelTimes.max = timeBetween end
    local c = travelTimes.count
    travelTimes.avg = (travelTimes.avg * c + timeBetween) / (c + 1)
    travelTimes.count = c + 1
    data.previous = {station = toStation, arrived = tick}

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
  end,

  [defines.train_state.wait_signal] = function(data, tick)
    log("wait signal")
    if not data.previous.station then
      return
    end
    local records = data.train.schedule.records
    local current = data.train.schedule.current
    local fromStation = data.previous.station
    local toStation = tostring(records[current].station)
    data.signalTimes[fromStation] = data.signalTimes[fromStation] or {[toStation] = {arrived = 0, current = 0, avg = 0, min= math.huge, max = 0, count = 0}}
    local signalTimes = data.signalTimes[fromStation][toStation]
    signalTimes.arrived = tick
  end,

  [defines.train_state.on_the_path] = function(data, tick)
    if data.previousState == defines.train_state.wait_signal then
      log("on the path")
      if not data.previous.station then
        return
      end
      local records = data.train.schedule.records
      local current = data.train.schedule.current
      local fromStation = data.previous.station
      local toStation = tostring(records[current].station)
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
  end,
}

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
    for id, data in pairs(global._trains) do
      data.id = id
      data.travelTimes = data.travelTimes or {}
      data.signalTimes = data.signalTimes or {}
    end
  end
}

remote.add_interface("trainstats", interface)


