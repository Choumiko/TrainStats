local Trains = {
  rolling_stock_types = {['locomotive'] = true, ['cargo-wagon'] = true},
  isSetup = false
}

--[[
Events:
  on_train_created:   a new train is created (#carriages == 1) -> no need to update any id
  on_train_destroyed: last rolling stock of a train is mined/destroyed -> remove data
  on_train_changed:   locomotive/wagon built and #carriages > 1 -> update saved LuaTrain reference and table index
  
LuaTrain becomes invalid when:
  a locomotive/wagon is added
  a locomotive/wagon  is removed/destroyed
  the player de-/couples a part (No event!)
  decoupling: can create 2 trains or 1 train and one part with only cargo wagons in it
  coupling: can merge 2 trains into 1 or just update one train when only cargo wagons are added
]]--

Trains.checkIntegrity = function()
  local count, validCount, incorrectIDs, incorrectLocoIDs, duplicates = 0, 0, 0, 0, 0
  for id, trainData in pairs(global._trains) do
    count = count + 1
    if trainData.train.valid then
      local actualID = Trains.get_train_id(trainData.train)
      local newLocoIDs = Trains.getLocomotiveIDs(trainData.train)
      for locoId, _ in pairs(newLocoIDs) do
        if not trainData._locomotiveIDs[locoId] then
          incorrectLocoIDs = incorrectLocoIDs + 1
        end
      end
      for locoID, _ in pairs(newLocoIDs) do
        if id ~= actualID and global._trains[locoID] then
          duplicates = duplicates + 1
        end
      end
      if id ~= actualID then
        incorrectIDs = incorrectIDs + 1
      end
      validCount = validCount + 1
    end
    log(id .. ": " .. serpent.line({ids = trainData._locomotiveIDs, valid = trainData.train.valid, length = trainData._length},{comment=false}))
  end
  log("Train integrity")
  log("Trains: " .. count)
  log("valid Trains: " .. validCount)
  log("invalid Trains: " .. count - validCount)
  log("incorrect IDs: " .. incorrectIDs)
  log("incorrect locoIds: " .. incorrectLocoIDs)
  log("duplicates: " .. duplicates)
  return (count == validCount and incorrectIDs == 0 and incorrectLocoIDs == 0 and duplicates == 0)
end

Trains.get_main_locomotive = function(train)
  if train.valid and
    train.locomotives and
    (#train.locomotives.front_movers > 0 or #train.locomotives.back_movers > 0)
  then
    return train.locomotives.front_movers and train.locomotives.front_movers[1] or train.locomotives.back_movers[1]
  end
end

Trains.get_train_id = function(train)
  local loco = Trains.get_main_locomotive(train)
  return loco and loco.unit_number
end

Trains.getLocomotiveIDs = function(train)
  local locomotives = {}
  local c = 0
  if train.locomotives then
    for _, loco in pairs(train.locomotives.front_movers) do
      c = c + 1
      locomotives[loco.unit_number] = loco
    end
    for _, loco in pairs(train.locomotives.back_movers) do
      c = c + 1
      locomotives[loco.unit_number] = loco
    end
  end
  return locomotives, c
end

Trains.getType = function(train)
  local s = ""
  local locos = train.locomotives
  if locos then
    s = locos.front_movers and s .. #locos.front_movers or s .. "0"
    s = train.cargo_wagons and s .. "-" .. #train.cargo_wagons or s .. "-0"
    s = locos.back_movers and s .. "-" .. #locos.back_movers or s
    return s
  end
end

Trains.add = function(train)
  assert(train.valid)
  local id = Trains.get_train_id(train)
  assert(not id or (id and not global._trains[id]))
  if id then
    global._trains[id] = {train = train, _locomotiveIDs = Trains.getLocomotiveIDs(train), _length = #train.carriages, id = id,
      previous = {station = false, arrived = 0, left = 0},
      travelTimes = {},
      signalTimes = {},
      waitingTimes = {},
      guis = {}
    }
    return id
  end
end

Trains.update = function(train, removeIDs)
  local id = Trains.get_train_id(train)
  assert(global._trains[id] or #removeIDs == 1)
  if removeIDs and #removeIDs > 0 then
    global._trains[id] = global._trains[removeIDs[1]]
    for _, rID in pairs(removeIDs) do
      global._trains[rID] = nil
    end
  end
  global._trains[id].train = train
  global._trains[id].id = id
  global._trains[id]._length = #train.carriages
  global._trains[id]._locomotiveIDs = Trains.getLocomotiveIDs(train)

  for checkId, loco in pairs(global._trains[id]._locomotiveIDs) do
    if checkId ~= id and global._trains[checkId] then
      assert(not global._trains[checkId].train.valid)
      assert(global._trains[Trains.get_train_id(loco.train)] and global._trains[Trains.get_train_id(loco.train)].train.valid)
      global._trains[checkId] = nil
    end
  end
  return id
end

Trains.revalidate = function()
  log("Revalidating trains")
  game.print("Revalidating trains")
  local trainsToAdd = {}
  local renames = {}
  for id, data in pairs(global._trains) do
    if not data.train.valid then
      --check locomotives for trains, should catch decoupled/coupled trains
      for locoID, loco in pairs(data._locomotiveIDs) do
        if loco.valid then
          local checkID = Trains.get_train_id(loco.train)
          if checkID == locoID and not global._trains[checkID] then
            trainsToAdd[checkID] = loco.train
          else
            log("updateTrain: " .. checkID)
            Trains.update(loco.train)
          end
        end
      end
    else
      if id ~= Trains.get_train_id(data.train) then
        log("rename train")
        renames[#renames + 1] = {id = id, train = data.train}
      end
    end
  end
  for _, data in pairs(renames) do
    if not global._trains[data.id] then
      log("addTrain 2")
      Trains.add(data.train)
    else
      log("updateTrain 2")
      Trains.update(data.train)
    end
  end
  for id, train in pairs(trainsToAdd) do
    if not global._trains[id] then
      log("addTrain 3")
      Trains.add(train)
    end
  end
  assert(Trains.checkIntegrity())
end

Trains.getData = function(train)
  local id = Trains.get_train_id(train)
  if id then
    local data = global._trains[id]
    if not data then
      Trains.add(train)
      return Trains.getData(train)
    end
    if data and not data.train.valid then
      log("invalid")
      Trains.revalidate(train)
    end
    data = global._trains[id]
    assert(data and data.train.valid)
    return (data and data.train.valid) and data
  end
end

Trains._on_rolling_stock_built = function(event)
  log("built")
  log(serpent.line(event,{comment=false}))
  local createdEntity = event.created_entity
  if createdEntity.valid and Trains.rolling_stock_types[createdEntity.type] then
    local createdTrain = createdEntity.train
    local newID = Trains.get_train_id(createdTrain)
    if not newID then return end
    local remove = {}
    if createdEntity.type == "locomotive" then
      --it's a new train
      if #createdTrain.carriages == 1 or (#createdTrain.locomotives.front_movers + #createdTrain.locomotives.back_movers == 1 )then
        Trains.add(createdTrain)
        Trains.checkIntegrity()
        return
      end
      --an existing train changed
      -- train ID changed, find the old one, copy to new and remove it
      if newID == createdEntity.unit_number then
        assert(not global._trains[newID])
        local oldIds = Trains.getLocomotiveIDs(createdTrain)
        for id, _ in pairs(oldIds) do
          if id ~= newID and global._trains[id] then
            assert(not global._trains[id].train.valid)
            remove[#remove + 1] = id
          end
        end
      end
    end
    Trains.update(createdTrain, remove)

    Trains.checkIntegrity()
  end
end

Trains._on_rolling_stock_removed = function(event)
  if not event.entity.valid or not Trains.rolling_stock_types[event.entity.type] then return end
  log("preremoved")
  log(serpent.line(event,{comment=false}))
  local removedEntity = event.entity
  local removedTrain = removedEntity.train
  local oldID = Trains.get_train_id(removedTrain)
  if not oldID then return end --train only has cargo wagons
  local length = #removedTrain.carriages
  local position = false
  local beforeLocos, afterLocos = {}, {}
  for i, carriage in pairs(removedTrain.carriages) do
    if carriage.type == "locomotive" and carriage ~= removedEntity then
      if not position then
        beforeLocos[#beforeLocos + 1] = carriage
      else
        afterLocos[#afterLocos + 1] = carriage
      end
    end
    if carriage == removedEntity then
      position = i
    end
  end
  if length == 1 or (#beforeLocos == 0 and #afterLocos == 0) then
    global._trains[oldID] = nil
    return
  end
  global._revalidateTrains = global._revalidateTrains or {}
  local revalidate = {id = oldID, carriages = {}}
  local before = position > 1 and removedTrain.carriages[position-1] or false
  local after = position < length and removedTrain.carriages[position+1] or false
  if before and #beforeLocos > 0 then
    revalidate.carriages[#revalidate.carriages+1] = before
    log("before")
  end
  if after and #afterLocos > 0 then
    revalidate.carriages[#revalidate.carriages+1] = after
    log("after")
  end
  global._revalidateTrains[#global._revalidateTrains + 1] = revalidate
  assert(global._trains[oldID])
  assert(global._trains[oldID].train.valid)
  Trains.checkIntegrity()
end

Trains.on_tick = function(event)
  if global._revalidateTrains then
    log("tick: " .. event.tick)
    for _, data in pairs(global._revalidateTrains) do
      local oldData = global._trains[data.id]
      local remove = true
      assert(oldData and not oldData.train.valid)
      for _, carriage in pairs(data.carriages) do
        local newID = Trains.get_train_id(carriage.train)
        if newID then
          if newID == data.id then
            log("update")
            Trains.update(carriage.train)
            remove = false
          else
            assert(not global._trains[newID])
            log("add")
            Trains.add(carriage.train)
          end
        end
      end
      if remove then
        global._trains[data.id] = nil
      end
    end
    global._revalidateTrains = nil
    Trains.checkIntegrity()
  end
end

return Trains
