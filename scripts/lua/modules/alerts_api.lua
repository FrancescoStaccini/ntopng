--
-- (C) 2013-19 - ntop.org
--

package.path = dirs.installdir .. "/scripts/lua/modules/?.lua;" .. package.path

local dirs = ntop.getDirs()
local json = require("dkjson")
local alert_endpoints = require("alert_endpoints_utils")
local alert_consts = require("alert_consts")
local os_utils = require("os_utils")
local do_trace = false

local alerts_api = {}

-- NOTE: sqlite can handle about 10-50 alerts/sec
local MAX_NUM_ENQUEUED_ALERT_PER_INTERFACE = 256
local ALERT_CHECKS_MODULES_BASEDIR = dirs.installdir .. "/scripts/callbacks/interface/alerts"

-- Just helpers
local str_2_periodicity = {
  ["min"]     = 60,
  ["5mins"]   = 300,
  ["hour"]    = 3600,
  ["day"]     = 86400,
}

local known_alerts = {}

-- ##############################################

local function getAlertEventQueue(ifid)
  return string.format("ntopng.cache.ifid_%d.alerts_events_queue", ifid)
end

-- ##############################################

local function makeAlertId(alert_type, subtype, periodicity, alert_entity)
  return(string.format("%s_%s_%s_%s", alert_type, subtype or "", periodicity or "", alert_entity))
end

function alerts_api:getId()
  return(makeAlertId(self.type_id, self.subtype, self.periodicity, self.entity_type_id))
end

-- ##############################################

local function alertErrorTraceback(msg)
  traceError(TRACE_ERROR, TRACE_CONSOLE, msg)
  traceError(TRACE_ERROR, TRACE_CONSOLE, debug.traceback())
end

-- ##############################################

local function getEntityDisabledAlertsCountersKey(ifid, entity, entity_val)
  return(string.format("ntopng.cache.alerts.ifid_%d.%d_%s", ifid, entity, entity_val))
end

local function incDisabledAlertsCount(ifid, granularity_id, entity, entity_val, alert_type)
  local key = getEntityDisabledAlertsCountersKey(ifid, entity, entity_val)

  -- NOTE: using separate keys based on granularity to avoid concurrency issues
  counter_key = string.format("%d_%d", granularity_id, alert_type)

  local val = tonumber(ntop.getHashCache(key, counter_key)) or 0
  val = val + 1
  ntop.setHashCache(key, counter_key, string.format("%d", val))
  return(val)
end

-- ##############################################

local function deleteEntityDisabledAlertsCountersKey(ifid, entity, entity_val, target_type)
  local key = getEntityDisabledAlertsCountersKey(ifid, entity, entity_val)
  local entity_counters = ntop.getHashAllCache(key) or {}

  for what, counter in pairs(entity_counters) do
    local parts = string.split(what, "_")

    if((parts) and (#parts == 2)) then
      local alert_type = tonumber(parts[2])

      if(alert_type == target_type) then
        ntop.delHashCache(key, what)
      end
    end
  end
end

-- ##############################################

function alerts_api.getEntityDisabledAlertsCounters(ifid, entity, entity_val)
  local key = getEntityDisabledAlertsCountersKey(ifid, entity, entity_val)
  local entity_counters = ntop.getHashAllCache(key) or {}
  local by_alert_type = {}

  for what, counter in pairs(entity_counters) do
    local parts = string.split(what, "_")

    if((parts) and (#parts == 2)) then
      local granularity_id = tonumber(parts[1])
      local alert_type = tonumber(parts[2])

      by_alert_type[alert_type] = by_alert_type[alert_type] or 0
      by_alert_type[alert_type] = by_alert_type[alert_type] + counter
    end
  end

  return(by_alert_type)
end

-- ##############################################

--! @brief Creates an alert object
--! @param metadata the information about the alert type and severity
--! @return an alert object on success, nil on error
function alerts_api:newAlert(metadata)
  if(metadata == nil) then
    alertErrorTraceback("alerts_api:newAlert() missing argument")
    return(nil)
  end

  local obj = table.clone(metadata)

  if type(obj.periodicity) == "string" then
    if(str_2_periodicity[obj.periodicity]) then
      obj.periodicity = str_2_periodicity[obj.periodicity]
    else
      alertErrorTraceback("unknown periodicity '".. obj.periodicity .."'")
      return(nil)
    end
  end

  if(type(obj.entity) ~= "string") then alertErrorTraceback("'entity' string required") end
  if(type(obj.type) ~= "string") then alertErrorTraceback("'type' string required") end
  if(type(obj.severity) ~= "string") then alertErrorTraceback("'severity' string required") end

  obj.entity_type_id = alertEntity(obj.entity)
  obj.type_id = alertType(obj.type)
  obj.severity_id = alertSeverity(obj.severity)
  obj.periodicity = obj.periodicity or 0

  if(type(obj.entity_type_id) ~= "number") then alertErrorTraceback("unknown entity_type '".. obj.entity .."'") end
  if(type(obj.type_id) ~= "number") then alertErrorTraceback("unknown alert_type '".. obj.type .."'") end
  if(type(obj.severity_id) ~= "number") then alertErrorTraceback("unknown severity '".. obj.severity .."'") end

  local alert_id = makeAlertId(obj.type_id, obj.subtype, obj.periodicity, obj.entity_type_id)
  known_alerts[alert_id] = obj

  setmetatable(obj, self)
  self.__index = self

  return(obj)
end

-- ##############################################

-- TODO change in "store"
--! @brief Triggers a new alert or refreshes an existing one (if already engaged)
--! @param entity_value the string representing the entity of the alert (e.g. "192.168.1.1")
--! @param alert_message the message (string) or json (table) to store
--! @param when (optional) the time when the trigger event occurs
--! @return true on success, false otherwise
function alerts_api:trigger(entity_value, alert_message, when)
  local force = false
  local msg = alert_message
  local ifid = interface.getId()
  when = when or os.time()

  if(type(alert_message) == "table") then
    msg = json.encode(alert_message)
  end

  if alerts_api.isEntityAlertDisabled(ifid, self.entity_type_id, entity_value, self.type_id) then
    incDisabledAlertsCount(ifid, -1, self.entity_type_id, entity_value, self.type_id)
    return(false)
  end

  local rv = interface.storeAlert(when, when, self.periodicity,
    self.type_id, self.subtype or "", self.severity_id,
    self.entity_type_id, entity_value, msg)

  if(self.entity == "host") then
    -- NOTE: for engaged alerts this operation is performed during trigger in C
    interface.incTotalHostAlerts(entity_value, self.type_id)
  end

  if(rv) then
    local action = "store"
    local message = {
      ifid = interface.getId(),
      entity_type = self.entity_type_id,
      entity_value = entity_value,
      type = self.type_id,
      severity = self.severity_id,
      message = msg,
      tstamp = when,
      action = action,
    }

    alert_endpoints.dispatchNotification(message, json.encode(message))
  end

  return(rv)
end

-- ##############################################

function alerts_api.parseAlert(metadata)
  local alert_id = makeAlertId(metadata.alert_type, metadata.alert_subtype, metadata.alert_periodicity, metadata.alert_entity)

  if known_alerts[alert_id] then
    return(known_alerts[alert_id])
  end

  -- new alert
  return(alerts_api:newAlert({
    entity = alertEntityRaw(metadata.alert_entity),
    type = alertTypeRaw(metadata.alert_type),
    severity = alertSeverityRaw(metadata.alert_severity),
    periodicity = tonumber(metadata.alert_periodicity),
    subtype = metadata.alert_subtype,
  }))
end

-- ##############################################

-- TODO unify alerts and metadata/notications format
function alerts_api.parseNotification(metadata)
  local alert_id = makeAlertId(alertType(metadata.type), metadata.alert_subtype, metadata.alert_periodicity, alertEntity(metadata.entity_type))

  if known_alerts[alert_id] then
    return(known_alerts[alert_id])
  end

  -- new alert
  return(alerts_api:newAlert({
    entity = metadata.entity_type,
    type = metadata.type,
    severity = metadata.severity,
    periodicity = metadata.periodicity,
    subtype = metadata.subtype,
  }))
end

-- ##############################################

-- TODO unify alerts and metadata/notications format
function alerts_api.alertNotificationToRecord(notif)
  return {
    alert_entity = alertEntity(notif.entity_type),
    alert_type = alertType(notif.type),
    alert_severity = alertSeverity(notif.severity),
    periodicity = notif.periodicity,
    alert_subtype = notif.subtype,
    alert_entity_val = notif.entity_value,
    alert_tstamp = notif.tstamp,
    alert_tstamp_end = notif.tstamp_end or notif.tstamp,
    alert_granularity = notif.granularity,
    alert_json = notif.message,
  }
end

-- ##############################################

local function get_alert_triggered_key(type_info)
  return(string.format("%d@%s", type_info.alert_type.alert_id, type_info.alert_subtype or ""))
end

-- ##############################################

local function enqueueAlertEvent(alert_event)
  local trim = nil
  local ifid = interface.getId()

  if(alert_event.ifid ~= ifid) then
    traceError(TRACE_ERROR, TRACE_CONSOLE, string.format("Wrong interface selected: expected %s, got %s", alert_event.ifid, ifid))
    return(false)
  end

  local event_json = json.encode(alert_event)
  local queue = getAlertEventQueue(ifid)

  if(ntop.llenCache(queue) > MAX_NUM_ENQUEUED_ALERT_PER_INTERFACE) then
    trim = math.ceil(MAX_NUM_ENQUEUED_ALERT_PER_INTERFACE/2)
    traceError(TRACE_WARNING, TRACE_CONSOLE, string.format("Alerts event queue too long: dropping %u alerts", trim))

    interface.incNumDroppedAlerts(trim)
  end

  ntop.rpushCache(queue, event_json, trim)
  return(true)
end

-- ##############################################

-- Performs the trigger/release asynchronously.
-- This is necessary both to avoid paying the database io cost inside
-- the other scripts and as a necessity to avoid a deadlock on the
-- host hash in the host.lua script
function alerts_api.processPendingAlertEvents(deadline)
  local ifnames = interface.getIfNames()

  for ifid, _ in pairs(ifnames) do
    interface.select(ifid)
    local queue = getAlertEventQueue(ifid)

    while(true) do
      local event_json = ntop.lpopCache(queue)

      if(not event_json) then
        break
      end

      local event = json.decode(event_json)

      if(event.action == "release") then
        interface.storeAlert(
          event.tstamp, event.tstamp_end, event.granularity,
          event.type, event.subtype or "", event.severity,
          event.entity_type, event.entity_value,
          event.message) -- event.message: nil for "release"
      end

      alert_endpoints.dispatchNotification(event, event_json)

      if(os.time() > deadline) then
        return(false)
      end
    end
  end

  return(true)
end

-- ##############################################

-- TODO: remove the "new_" prefix and unify with other alerts

--! @brief Trigger an alert of given type on the entity
--! @param entity_info data returned by one of the entity_info building functions
--! @param type_info data returned by one of the type_info building functions
--! @param when (optional) the time when the release event occurs
--! @note The actual trigger is performed asynchronously
--! @return true on success, false otherwise
function alerts_api.new_trigger(entity_info, type_info, when)
  when = when or os.time()
  local ifid = interface.getId()
  local granularity_sec = type_info.alert_granularity and type_info.alert_granularity.granularity_seconds or 0
  local granularity_id = type_info.alert_granularity and type_info.alert_granularity.granularity_id or nil
  local subtype = type_info.alert_subtype or ""
  local alert_json = json.encode(type_info.alert_type_params)
  local is_disabled = alerts_api.isEntityAlertDisabled(ifid, entity_info.alert_entity.entity_id, entity_info.alert_entity_val, type_info.alert_type.alert_id)

  if(granularity_id ~= nil) then
    local triggered = true
    local alert_key_name = get_alert_triggered_key(type_info)
    local params = {alert_key_name, granularity_id,
      type_info.alert_type.severity.severity_id, type_info.alert_type.alert_id,
      subtype, alert_json, is_disabled
    }

    if((host.storeTriggeredAlert) and (entity_info.alert_entity.entity_id == alertEntity("host"))) then
      triggered = host.storeTriggeredAlert(table.unpack(params))
    elseif((interface.storeTriggeredAlert) and (entity_info.alert_entity.entity_id == alertEntity("interface"))) then
      triggered = interface.storeTriggeredAlert(table.unpack(params))
    elseif((network.storeTriggeredAlert) and (entity_info.alert_entity.entity_id == alertEntity("network"))) then
      triggered = network.storeTriggeredAlert(table.unpack(params))
    end

    if(not triggered) then
      if(do_trace) then print("[Don't Trigger alert (already triggered?) @ "..granularity_sec.."] "..
        entity_info.alert_entity_val .."@"..type_info.alert_type.i18n_title..":".. subtype .. "\n") end
      return(false)
    elseif(is_disabled) then
      if(do_trace) then print("[COUNT Disabled alert @ "..granularity_sec.."] "..
        entity_info.alert_entity_val .."@"..type_info.alert_type.i18n_title..":".. subtype .. "\n") end

      incDisabledAlertsCount(ifid, granularity_id, entity_info.alert_entity.entity_id, entity_info.alert_entity_val, type_info.alert_type.alert_id)
    else
      if(do_trace) then print("[TRIGGER alert @ "..granularity_sec.."] "..
        entity_info.alert_entity_val .."@"..type_info.alert_type.i18n_title..":".. subtype .. "\n") end
    end
  end

  local action = ternary((granularity_id ~= nil), "engaged", "stored")

  local alert_event = {
    ifid = ifid,
    granularity = granularity_sec,
    entity_type = entity_info.alert_entity.entity_id,
    entity_value = entity_info.alert_entity_val,
    type = type_info.alert_type.alert_id,
    severity = type_info.alert_type.severity.severity_id,
    message = alert_json,
    subtype = subtype,
    tstamp = when,
    action = action,
  }

  return(enqueueAlertEvent(alert_event))
end

-- ##############################################

--! @brief Release an alert of given type on the entity
--! @param entity_info data returned by one of the entity_info building functions
--! @param type_info data returned by one of the type_info building functions
--! @param when (optional) the time when the release event occurs
--! @note The actual release is performed asynchronously
--! @return true on success, false otherwise
function alerts_api.release(entity_info, type_info, when)
  local when = when or os.time()
  local granularity_sec = type_info.alert_granularity and type_info.alert_granularity.granularity_seconds or 0
  local granularity_id = type_info.alert_granularity and type_info.alert_granularity.granularity_id or nil
  local subtype = type_info.alert_subtype or ""
  local alert_key_name = get_alert_triggered_key(type_info)
  local released = nil

  if((host.releaseTriggeredAlert) and (entity_info.alert_entity.entity_id == alertEntity("host"))) then
    released = host.releaseTriggeredAlert(alert_key_name, granularity_id, when)
  elseif((interface.releaseTriggeredAlert) and (entity_info.alert_entity.entity_id == alertEntity("interface"))) then
    released = interface.releaseTriggeredAlert(alert_key_name, granularity_id, when)
  elseif((network.releaseTriggeredAlert) and (entity_info.alert_entity.entity_id == alertEntity("network"))) then
    released = network.releaseTriggeredAlert(alert_key_name, granularity_id, when)
  else
    alertErrorTraceback("Unsupported entity" .. entity_info.alert_entity.entity_id)
    return(false)
  end

  if(released == nil) then
    if(do_trace) then print("[Dont't Release alert (not triggered?) @ "..granularity_sec.."] "..
      entity_info.alert_entity_val .."@"..type_info.alert_type.i18n_title..":".. subtype .. "\n") end
    return(false)
  else
    if(do_trace) then print("[RELEASE alert @ "..granularity_sec.."] "..
        entity_info.alert_entity_val .."@"..type_info.alert_type.i18n_title..":".. subtype .. "\n") end
  end

  local alert_event = {
    ifid = interface.getId(),
    granularity = granularity_sec,
    entity_type = entity_info.alert_entity.entity_id,
    entity_value = entity_info.alert_entity_val,
    type = type_info.alert_type.alert_id,
    severity = type_info.alert_type.severity.severity_id,
    subtype = subtype,
    tstamp = released.alert_tstamp,
    tstamp_end = released.alert_tstamp_end,
    message = released.alert_json,
    action = "release",
  }

  return(enqueueAlertEvent(alert_event))
end

-- ##############################################

-- Convenient method to release multiple alerts on an entity
function alerts_api.releaseEntityAlerts(entity_info, alerts)
  for _, alert in pairs(alerts) do
    alerts_api.release(entity_info, {
      alert_type = alert_consts.alert_types[alertTypeRaw(alert.alert_type)],
      alert_subtype = alert.alert_subtype,
      alert_granularity = alert_consts.alerts_granularities[sec2granularity(alert.alert_granularity)],
    })
  end
end

-- ##############################################
-- entity_info building functions
-- ##############################################

function alerts_api.hostAlertEntity(hostip, hostvlan)
  return {
    alert_entity = alert_consts.alert_entities.host,
    -- NOTE: keep in sync with C (Alertable::setEntityValue)
    alert_entity_val = hostinfo2hostkey({ip = hostip, vlan = hostvlan}, nil, true)
  }
end

-- ##############################################

function alerts_api.interfaceAlertEntity(ifid)
  return {
    alert_entity = alert_consts.alert_entities.interface,
    -- NOTE: keep in sync with C (Alertable::setEntityValue)
    alert_entity_val = string.format("iface_%d", ifid)
  }
end

-- ##############################################

function alerts_api.networkAlertEntity(network_cidr)
  return {
    alert_entity = alert_consts.alert_entities.network,
    -- NOTE: keep in sync with C (Alertable::setEntityValue)
    alert_entity_val = network_cidr
  }
end

-- ##############################################
-- type_info building functions
-- ##############################################

function alerts_api.thresholdCrossType(granularity, metric, value, operator, threshold)
  local res = {
    alert_type = alert_consts.alert_types.threshold_cross,
    alert_subtype = string.format("%s_%s", granularity, metric),
    alert_granularity = alert_consts.alerts_granularities[granularity],
    alert_type_params = {
      metric = metric, value = value,
      operator = operator, threshold = threshold,
    }
  }
  return(res)
end

-- ##############################################

function alerts_api.anomalyType(anomal_name, alert_type, value, threshold)
  local res = {
    alert_type = alert_type,
    alert_subtype = anomal_name,
    alert_granularity = alert_consts.alerts_granularities.min,
    alert_type_params = {
      value = value,
      threshold = threshold,
    }
  }

  return(res)
end

-- ##############################################

function alerts_api.load_check_modules(subdir, str_granularity)
  local checks_dir = os_utils.fixPath(ALERT_CHECKS_MODULES_BASEDIR .. "/" .. subdir)
  local available_modules = {}

  package.path = checks_dir .. "/?.lua;" .. package.path

  for fname in pairs(ntop.readdir(checks_dir)) do
    if ends(fname, ".lua") then
      local modname = string.sub(fname, 1, string.len(fname) - 4)
      local check_module = require(modname)

      if check_module.check_function then
	 if check_module.granularity and str_granularity then
	    -- When the module specify one or more granularities
	    -- at which checks have to be run, the module is only
	    -- loaded after checking the granularity
	    for _, gran in pairs(check_module.granularity) do
	       if gran == str_granularity then
		  available_modules[modname] = check_module
		  break
	       end
	    end
	 else
	    -- When no granularity is explicitly specified
	    -- in the module, then the check it is assumed to
	    -- be run for every granularity and the module is
	    -- always loaded
	    available_modules[modname] = check_module
	 end
      end
    end
  end

  return available_modules
end

-- ##############################################

function alerts_api.threshold_check_function(params)
  local alarmed = false
  local value = params.check_module.get_threshold_value(params.granularity, params.entity_info)
  local threshold_config = params.alert_config

  local threshold_edge = tonumber(threshold_config.edge)
  local threshold_type = alerts_api.thresholdCrossType(params.granularity, params.check_module.key, value, threshold_config.operator, threshold_edge)

  if(threshold_config.operator == "lt") then
    if(value < threshold_edge) then alarmed = true end
  else
    if(value > threshold_edge) then alarmed = true end
  end

  if(alarmed) then
    return(alerts_api.new_trigger(params.alert_entity, threshold_type))
  else
    return(alerts_api.release(params.alert_entity, threshold_type))
  end
end

-- ##############################################

function alerts_api.check_anomaly(anomal_name, alert_type, alert_entity, entity_anomalies, anomal_config)
  local anomaly = entity_anomalies[anomal_name] or {value = 0}
  local value = anomaly.value
  local anomaly_type = alerts_api.anomalyType(anomal_name, alert_type, value, anomal_config.threshold)

  if(do_trace) then print("[Anomaly check] ".. alert_entity.alert_entity_val .." ["..anomal_name.."]\n") end

  if(anomaly ~= nil) then
    return(alerts_api.new_trigger(alert_entity, anomaly_type))
  else
    return(alerts_api.release(alert_entity, threshold_type))
  end
end

-- ##############################################

local function delta_val(reg, metric_name, granularity, curr_val)
   local granularity_num = granularity2id(granularity)
   local key = string.format("%s:%s", metric_name, granularity_num)

   -- Read cached value and purify it
   local prev_val = reg.getCachedAlertValue(key, granularity_num)
   prev_val = tonumber(prev_val) or 0
   -- Save the value for the next round
   reg.setCachedAlertValue(key, tostring(curr_val), granularity_num)

   -- Compute the delta
   return curr_val - prev_val
end

-- ##############################################

function alerts_api.host_delta_val(metric_name, granularity, curr_val)
  return(delta_val(host --[[ the host Lua reg ]], metric_name, granularity, curr_val))
end

function alerts_api.interface_delta_val(metric_name, granularity, curr_val)
  return(delta_val(interface --[[ the interface Lua reg ]], metric_name, granularity, curr_val))
end

function alerts_api.network_delta_val(metric_name, granularity, curr_val)
  return(delta_val(network --[[ the network Lua reg ]], metric_name, granularity, curr_val))
end

-- ##############################################

function alerts_api.application_bytes(info, application_name)
   local curr_val = 0

   if info["ndpi"] and info["ndpi"][application_name] then
      curr_val = info["ndpi"][application_name]["bytes.sent"] + info["ndpi"][application_name]["bytes.rcvd"]
   end

   return curr_val
end

-- ##############################################

function alerts_api.category_bytes(info, category_name)
   local curr_val = 0

   if info["ndpi_categories"] and info["ndpi_categories"][category_name] then
      curr_val = info["ndpi_categories"][category_name]["bytes.sent"] + info["ndpi_categories"][category_name]["bytes.rcvd"]
   end

   return curr_val
end

-- ##############################################

function alerts_api.threshold_cross_input_builder(gui_conf, input_id, value)
  value = value or {}
  local gt_selected = ternary(value[1] == "gt", ' selected="selected"', '')
  local lt_selected = ternary(value[1] == "lt", ' selected="selected"', '')
  local input_op = "op_" .. input_id
  local input_val = "value_" .. input_id

  return(string.format([[<select name="%s">
  <option value="gt"%s>&gt;</option>
  <option value="lt"%s>&lt;</option>
</select> <input type="number" class="text-right form-control" min="%s" max="%s" step="%s" style="display:inline; width:12em;" name="%s" value="%s"/> <span>%s</span>]],
    input_op, gt_selected, lt_selected,
    gui_conf.field_min or "0", gui_conf.field_max or "", gui_conf.field_step or "1",
    input_val, value[2], i18n(gui_conf.i18n_field_unit))
  )
end

-- ##############################################

local function getEntityDisabledAlertsBitmapKey(ifid, entity, entity_val)
  return string.format("ntopng.prefs.alerts.ifid_%d.disabled_alerts.__%s__%s", ifid, entity, entity_val)
end

-- ##############################################

function alerts_api.getEntityAlertsDisabled(ifid, entity, entity_val)
  local bitmap = tonumber(ntop.getPref(getEntityDisabledAlertsBitmapKey(ifid, entity, entity_val))) or 0
  -- traceError(TRACE_NORMAL, TRACE_CONSOLE, string.format("ifid: %d, entity: %s, val: %s -> bitmap=%x", ifid, alertEntityRaw(entity), entity_val, bitmap))
  return(bitmap)
end

-- ##############################################

function alerts_api.setEntityAlertsDisabled(ifid, entity, entity_val, bitmap)
  local key = getEntityDisabledAlertsBitmapKey(ifid, entity, entity_val)

  if(bitmap == 0) then
    ntop.delCache(key)
  else
    ntop.setPref(key, string.format("%u", bitmap))
  end
end

-- ##############################################

local function toggleEntityAlert(ifid, entity, entity_val, alert_type, disable)
  alert_type = tonumber(alert_type)
  bitmap = alerts_api.getEntityAlertsDisabled(ifid, entity, entity_val)

  if(disable) then
    bitmap = ntop.bitmapSet(bitmap, alert_type)
  else
    bitmap = ntop.bitmapClear(bitmap, alert_type)
    deleteEntityDisabledAlertsCountersKey(ifid, entity, entity_val, alert_type)
  end

  alerts_api.setEntityAlertsDisabled(ifid, entity, entity_val, bitmap)
  return(bitmap)
end

-- ##############################################

function alerts_api.disableEntityAlert(ifid, entity, entity_val, alert_type)
  return(toggleEntityAlert(ifid, entity, entity_val, alert_type, true))
end

-- ##############################################

function alerts_api.enableEntityAlert(ifid, entity, entity_val, alert_type)
  return(toggleEntityAlert(ifid, entity, entity_val, alert_type, false))
end

-- ##############################################

function alerts_api.isEntityAlertDisabled(ifid, entity, entity_val, alert_type)
  local bitmap = alerts_api.getEntityAlertsDisabled(ifid, entity, entity_val)
  return(ntop.bitmapIsSet(bitmap, tonumber(alert_type)))
end

-- ##############################################

function alerts_api.hasEntitiesWithAlertsDisabled(ifid)
  return(table.len(ntop.getKeysCache(getEntityDisabledAlertsBitmapKey(ifid, "*", "*"))) > 0)
end

-- ##############################################

function alerts_api.listEntitiesWithAlertsDisabled(ifid)
  local keys = ntop.getKeysCache(getEntityDisabledAlertsBitmapKey(ifid, "*", "*")) or {}
  local res = {}

  for key in pairs(keys) do
    local parts = string.split(key, "__")

    if((parts) and (#parts == 3)) then
      local entity = tonumber(parts[2])
      local entity_val = parts[3]

      res[entity] = res[entity] or {}
      res[entity][entity_val] = true
    end
  end

  return(res)
end

-- ##############################################

return(alerts_api)
