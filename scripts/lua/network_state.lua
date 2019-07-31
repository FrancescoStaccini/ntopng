--
-- (C) 2019 - ntop.org
--

dirs = ntop.getDirs()
package.path = dirs.installdir .. "/scripts/lua/?.lua;" .. package.path
if((dirs.scriptdir ~= nil) and (dirs.scriptdir ~= "")) then package.path = dirs.scriptdir .. "/lua/modules/?.lua;" .. package.path end
require "lua_utils"

local network_state = {}
local if_stats = interface.getStats()

--[[
--TODO: normalizza i nomi delle funzioni: aaa_bbb_ccc() e non aaaBbbCc()
--TODO: documenta meglio le funzioni
]]
--------------------------------------------------------------------------------------------------------------
--os.time() --> [...] the number of seconds since some given start time (the "epoch")

--note: tieni conto che la guardia della deadline è (os.time() >= deadline))
local deadline = 3 --seconds
local group_of = 10 --paginazione 

--[[ 

idea: check quando/se la deadline è scaduta (e avverto l'utente), ma dovrei modificare callback_utils.lua 

note: il chiamante può decidere la deadline (es. vuole fare più iterazioni, dovrà calcolarsi il tempo a modo suo) 

"type"    contiene il tipo dell'entità su cui iterare, unico campo obbligatorio 
"res"     tabella col risultato, indicizzato per "name". Necessario se si vuole il risultato della callback di default
"params"  array contenente il nome (stringhe) dei parametri che interessano al chiamante
          (se params cotiene un campo non presente tra le stats dell'entità, tale valore sarà nil)
]]
function network_state.get_stats( type, res, params, caller_deadline,  caller_callback) 
  local callback_utils = require "callback_utils"
  local ret = false

  --note: works only for "first level" structure, don't works for inner tables
  local function param_callback(name, stats) --note: is the default callback
    local tmp = {}
    if not res then return false end

    if not params then
      tmp = stats
    else
      for _,v in pairs(params) do
        if stats[v] then 
          tmp[v] = stats[v] 
        end
      end
    end
    
    res[name] = tmp
    return true
  end 

  local callback = param_callback
  if caller_callback then callback = caller_callback end

  local custom_deadline = deadline
  if caller_deadline then custom_deadline = caller_deadline end 

  --note: l'iteratore per gli host remoti non è implementato come utils, ma c'è tra i batched iterator
  if type == "flow" then 
    --note: per i flow, nella callback -->  name = flow_key  &  stats = flow
    ret = callback_utils.foreachFlow(ifname, os.time() + custom_deadline, callback )
  elseif type == "devices" then 
    ret = callback_utils.foreachDevice(ifname, os.time() + custom_deadline, callback )
  elseif type == "host" then 
    ret = callback_utils.foreachHost(ifname, os.time() + custom_deadline, callback )
  elseif type == "localhost" then 
    ret = callback_utils.foreachLocalHost(ifname, os.time() + custom_deadline, callback )
  elseif type == "localhost_ts" then
       --note: per i local rrd host, nella callback -->  stats = host_ts
       --TODO: decidi se tenere a true o false il terzo campo, quelli dei "dettagli"
       --note: PARE che se è a true ti da i valori all'ultimo istante, a false ti da alcune(?) info sull'host stesso
    ret = callback_utils.foreachLocalRRDHost(ifname, os.time() + custom_deadline, true, callback )
  else
    ret = false
  end

  return ret
end

----------------------------------------------------------------------------------------------------------

--return ndpi categoty table [ "category_name" = "bytes" ]
function network_state.check_ndpi_categories()
  local t = {} 
  for i,v in pairs(if_stats.ndpi_categories) do
     t[tostring(i)] = if_stats.ndpi_categories[i].bytes 
  end
  
  return t
end

--##############################################################################################

--return ndpi proto table [ "proto_name" = "bytes sent + rcvd" ]
function network_state.get_ndpi_proto_traffic_volume()
  local t, ndpi_stats = {}, interface.getActiveFlowsStats() 
  local j = 1

  for i,v in pairs( ndpi_stats.ndpi ) do
    t[i] =  v["bytes.sent"] + v["bytes.rcvd"] 
  end
  
  return t
end

--##############################################################################################

--return a table with name and volume-percentage for each ndpi traffic category
function network_state.check_traffic_categories()
  local traffic = network_state.check_ndpi_categories()
  local tot = 1
  local res = {}

  for i,v in pairs(traffic) do
      tot = tot + v
  end

  for i,v in pairs(traffic) do
      table.insert( res, {name = i, perc = math.floor(( v / tot ) * 1000) / 10, bytes = v } )
  end

  local function compare(a, b) return a.perc > b.perc end

  table.sort( res, compare )

  return res
end

--##############################################################################################

--return the name and percentage of the ndpi proto that has generated more traffic
function network_state.check_top_traffic_application_protocol_categories()
  local traffic = network_state.check_ndpi_categories()
  local name, max, perc, tot = "non specificato", 0, 0, 1

  for i,v in pairs(traffic) do
    tot = tot + v
    if max < v then 
       name, max = i, v
    end    
  end
  perc = math.floor(( max / tot ) * 100) 
  return name, perc
end

--##############################################################################################

--return an array-table of all ndpi_proto_name and traffic percentage
function network_state.check_top_application_protocol()
  local t, tot = {}, 1
  local proto_app = network_state.get_ndpi_proto_traffic_volume()
  local c, res = 0, {}

  for i,v in pairs(proto_app) do tot = tot + v end

  for i,v in pairs(proto_app) do
    table.insert(res, {name = i, bytes = v, percentage = math.floor( (v / tot) * 100 ) } )
  end

  local function compare(a,b) return a.bytes > b.bytes end
  table.sort(res, compare)

  return res
end

--##############################################################################################

--return table with just some interface stats
function network_state.check_ifstats_table()
  local t = {
    device_num = if_stats.stats.devices,
    flow_num = if_stats.stats.flows,
    host_num = if_stats.stats.hosts,
    total_bytes = if_stats.stats.bytes,
    local_host_num = if_stats.stats.local_hosts,
    device_num = if_stats.stats.devices
  }
  return t
end

--##############################################################################################

function network_state.check_devices_type() 
  local discover = require "discover_utils" 
  local res= {}

  for i,v in pairs(interface.getMacDeviceTypes() ) do
    res[discover.devtype2string(i)] = v
  end 

  return res, if_stats.stats.devices
end

--##############################################################################################

--return respectively: 1) total percentage of goodput, 2) num of bad goodput client, 3) num of bad goodput server, 4) num of total flow
function network_state.get_aggregated_TCP_flow_goodput_percentage()
  local bad_gp_client, bad_gp_server, flow_tot, prbl = 0,0,0,0
  local seen = 0

  repeat
    hoinfo = interface.getHostsInfo(true, "column_", group_of)
    tot = hoinfo.numHosts

    for i,v in pairs( hoinfo["hosts"] ) do
      local afas, afac = hoinfo["hosts"][i]["active_flows.as_server"], hoinfo["hosts"][i]["active_flows.as_client"]
      local bgc, bgs = hoinfo["hosts"][i]["low_goodput_flows.as_client"], hoinfo["hosts"][i]["low_goodput_flows.as_server"]
  
      flow_tot = flow_tot + afac + afas
      bad_gp_client = bad_gp_client + bgc
      bad_gp_server = bad_gp_server + bgs
    end 
    
    seen = seen + group_of
  until (seen < tot) or (os.time() > deadline)

  local perc = 100 - math.floor( (bad_gp_client + bad_gp_server) / flow_tot) * 100 

  return perc, bad_gp_client, bad_gp_server, flow_tot
end

--##############################################################################################

--!!NOTE!!: La sto lasciando SOLO percompatibilità con nAssistant01, appena sistemato l'assistente in italiano va cancellata/spostata/rinominata
--return respectively: state of goodput, number of total flow, total number of bad goodput flow
function network_state.check_TCP_flow_goodput()
  local bad_gp_client, bad_gp_server, flow_tot, prbl = 0,0,0,0
  local seen = 0

  repeat
    hoinfo = interface.getHostsInfo(true, "column_", group_of)
    tot = hoinfo.numHosts

    for i,v in pairs( hoinfo["hosts"] ) do
      local afas, afac = hoinfo["hosts"][i]["active_flows.as_server"], hoinfo["hosts"][i]["active_flows.as_client"]
      local bgc, bgs = hoinfo["hosts"][i]["low_goodput_flows.as_client"], hoinfo["hosts"][i]["low_goodput_flows.as_server"]
  
      flow_tot = flow_tot + afac + afas
      bad_gp_client = bad_gp_client + bgc
      bad_gp_server = bad_gp_server + bgs
    end 
    
    seen = seen + group_of
  until (seen < tot) or (os.time() > deadline)

  --'sta parte di dialogo va messa dentro l'assistente, in questo file non si tratta la parte grammaticale
  local perc, state = 100 - math.floor( (bad_gp_client + bad_gp_server) / flow_tot) * 100 
  if perc > 90 then 
    state = "complessivamente ottima" 
  elseif perc > 80 then 
    state = "complessivamente buona"
  elseif perc > 70 then
    state = "complessivamente mediocre"
  else 
    state = "complessivamente bassa" 
  end

  return state, flow_tot, (bad_gp_client + bad_gp_server)
end

--##############################################################################################

--return a table with tot traffic, remote/local percentage and pkt drop
function network_state.check_net_communication()

  local tot = if_stats.localstats.bytes.local2remote + if_stats.localstats.bytes.remote2local + 
            if_stats.localstats.bytes.remote2remote + if_stats.localstats.bytes.local2local
  local t = {
    total_traffic = tot,
    prc_remote2local_traffic = math.floor((if_stats.localstats.bytes.remote2local / tot) * 100),
    prc_local2remote_traffic = math.floor((if_stats.localstats.bytes.local2remote / tot) * 100),
    prc_pkt_drop = math.floor( (if_stats.tcpPacketStats.lost / if_stats.stats.packets) * 100000 ) / 1000, --TODO: assicurarsi che "if_stats.stats.packets" si riferisca ai pacchetti tcp
    num_pkt_drop = if_stats.tcpPacketStats.lost,
    num_tot_pkt = if_stats.stats.packets
  }
  return t
  
end

--##############################################################################################

--return a table ["breed_name" = "perentage of that breed"], number of blacklisted active host and a flag to report Dangerous traffic
function network_state.check_bad_hosts_and_app()
  local blacklisted, danger_flag = 0, false
  local callback = require "callback_utils"

  local function mycallback( hostname, hoststats )
      if  hoststats.is_blacklisted then blacklisted = blacklisted + 1  end
  end
  network_state.get_stats("host", nil, nil, nil, mycallback)

  local j, breeds, tot, bytes = 1, {}, 0, 0
  for i,v in pairs(if_stats["ndpi"]) do
    bytes = if_stats["ndpi"][i]["bytes.sent"] + if_stats["ndpi"][i]["bytes.rcvd"]
    breeds[j] ={ ["name"] = if_stats["ndpi"][i]["breed"], ["bytes"] = bytes  }
    tot = tot + bytes
    j = j + 1
  end

  local res = {}
  for i,v in ipairs(breeds) do 
    if res[ breeds[i]["name"] ] ~= nil then 
      res[breeds[i]["name"] ] = res[breeds[i]["name"] ] + breeds[i]["bytes"]
    else
      res[breeds[i]["name"] ] = breeds[i]["bytes"]
    end
  end

  for i,v in pairs(res) do 
    if i == "Dangerous" then danger_flag = true end
    res[i] = { perc = math.floor( (res[i] / tot) * 1000 ) / 10, bytes = v }
  end

  return res, blacklisted, danger_flag
end

--##############################################################################################

--return a table with ndpi application name and traffic volume for each ndpi application with "Dangerous" breed 
function network_state.check_dangerous_traffic()
  local res= {}
  local tot_bytes = 0

  for i,v in pairs(if_stats["ndpi"]) do
    if v.breed == "Dangerous" then 
      tot_bytes = v["bytes.rcvd"] + v["bytes.sent"]
      v["total_bytes"] = tot_bytes 
      v["name"] = i
      table.insert( res, v )
    end
  end

  if #res > 0 then
    return res
  else 
    return nil 
  end
end

--##############################################################################################
---------------------------------------- ALERTS ------------------------------------------------
--##############################################################################################
--TODO: NOTIFICHE se possibile. Notificare almeno gli allarmi importanti
--      distingui/separa/etichetta gli allarmi engaged - released - di flusso...
--      di sicuro c'è da far capire bene: Soggetto, stato allarme, gravità, tipo. [VEDI APPUNTI ALERT] 
--  !!  funzioni per controllare gloi alert per host/mac

--NOTE: le funzion iattuali si riferiscono alla totalità degli alert
require "alert_utils"

function network_state.get_alerts()--TODO: cambia nome in get_aletrs
  local engaged_alerts = getAlerts("engaged", getTabParameters(_GET, "engaged"))
  local past_alerts    = getAlerts("historical", getTabParameters(_GET, "historical"))
  local flow_alerts    = getAlerts("historical-flows", getTabParameters(_GET, "historical-flows"))

  return engaged_alerts, past_alerts, flow_alerts
end

--##############################################################################################

function network_state.get_num_alerts_and_severity()
  -- local num_engaged_alerts  = getNumAlerts("engaged", getTabParameters(_GET, "engaged"))
  -- local num_past_alerts     = getNumAlerts("historical", getTabParameters(_GET, "historical"))
  -- local num_flow_alerts     = getNumAlerts("historical-flows", getTabParameters(_GET,"historical-flows"))
  -- local engaged_alerts      = getAlerts("engaged", getTabParameters(_GET, "engaged"))
  -- local past_alerts         = getAlerts("historical", getTabParameters(_GET, "historical"))
  -- local flow_alerts         = getAlerts("historical-flows", getTabParameters(_GET, "historical-flows"))

  -- local severity = {} --severity: (none,) info, warning, error
  -- local alert_num = num_engaged_alerts + num_past_alerts + num_flow_alerts

  -- local function severity_cont(alerts, severity_table )
  --   local severity_text = ""

  --   for i,v in pairs(alerts) do
  --     if v.alert_severity then 
  --       severity_text = alertSeverityLabel(v.alert_severity, true)
  --       severity_table[severity_text] = (severity_table[severity_text] or 0) + 1 
  --     end
  --   end
  -- end

  -- if alert_num > 0 then
  --   severity_cont(engaged_alerts, severity)
  --   severity_cont(   flow_alerts, severity)
  --   severity_cont(   past_alerts, severity)
  -- end

  -- return alert_num, severity
end

--##############################################################################################

function network_state.alerts_details()
  -- local engaged_alerts, past_alerts, flow_alerts = network_state.get_alerts() 
  -- local tmp_alerts, alerts = {}, {}
  -- local limit= 3 --temporary limit, add effective selection criterion (eg. text limit is 640 char )

  -- j = 0
  -- for i,v in pairs(engaged_alerts)  do
  --   if j < limit then 
  --      table.insert( tmp_alerts, v )
  --      j = j+1
  --   else break end
  -- end

  -- j = 0
  -- for i,v in pairs(flow_alerts)  do
  --   if j < limit then 
  --      table.insert( tmp_alerts, v )
  --      j = j+1
  --   else break end
  -- end

  -- j = 0
  -- for i,v in pairs(past_alerts)  do
  --   if j < limit then 
  --      table.insert( tmp_alerts, v )
  --      j = j+1
  --   else break end
  -- end

  -- local alert_type, rowid, t_stamp, srv_addr, srv_port, cli_addr, cli_port, severity, alert_json  

  -- for i,v in pairs(tmp_alerts) do 

  --   if v.alert_type       then alert_type = alertTypeLabel( v.alert_type, true )      else  alert_type      = "Sconosciuto" end
  --   if v.rowid            then rowid  =  v.rowid                                      else  rowid           = "Sconosciuto" end
  --   if v.alert_tstamp     then t_stamp =  os.date( "%c", tonumber(v.alert_tstamp))    else  t_stamp         = "Sconosciuto" end
  --   if v.srv_addr         then srv_addr = v.srv_addr                                  else  srv_addr        = "Sconosciuto" end
  --   if v.srv_port         then srv_port = v.srv_port                                  else  srv_port        = "Sconosciuto" end
  --   if v.cli_addr         then cli_addr = v.cli_addr                                  else  cli_addr        = "Sconosciuto" end
  --   if v.cli_port         then cli_port = v.cli_port                                  else  cli_port        = "Sconosciuto" end
  --   if v.alert_severity   then severity = alertSeverityLabel(v.alert_severity, true)  else  severity        = "Sconosciuto" end
  --   if v.alert_json       then alert_json = v.alert_json                              else  alert_json      = "Sconosciuto" end 
    
  --   local e = {
  --     ID            = rowid,
  --     Tipo          = alert_type,
  --     Scattato      = t_stamp,
  --     Pericolosita  = severity,
  --     IP_Server     = srv_addr,
  --     Porta_Server  = srv_port,
  --     IP_Client     = cli_addr,
  --     Porta_Client  = cli_port,
  --     JSON_info     = alert_json --sono necessarie le JSON INFO? 
  --   }

  --   table.insert( alerts, e )
  -- end

  -- if #alerts > 0 then 
  --   return alerts
  -- else
  --   return nil
  -- end

end
  
--##############################################################################################
------------------------------------------------------------------------------------------------
--##############################################################################################

return network_state



--[[

--TODO: includi i flow status nelle info del traffico! prima però studiali
-- questi status qui sotto si ottengono iterando sui singoli flussi (con get_stats(...)) o in maniera aggregata da interface.getFlowsStatus()

--inoltre chiedi a luca se sono solo per ntop edge o se posso comunque usarli

function getFlowStatusTypes()
   local entries = {
   [0]  = i18n("flow_details.normal"),
   [1]  = i18n("flow_details.slow_tcp_connection"),
   [2]  = i18n("flow_details.slow_application_header"),
   [3]  = i18n("flow_details.slow_data_exchange"),
   [4]  = i18n("flow_details.low_goodput"),
   [5]  = i18n("flow_details.suspicious_tcp_syn_probing"),
   [6]  = i18n("flow_details.tcp_connection_issues"),
   [7]  = i18n("flow_details.suspicious_tcp_probing"),
   [8]  = i18n("flow_details.flow_emitted"),
   [9]  = i18n("flow_details.tcp_connection_refused"),
   [10] = i18n("flow_details.ssl_certificate_mismatch"),
   [11] = i18n("flow_details.dns_invalid_query"),
   [12] = i18n("flow_details.remote_to_remote"),
   [13] = i18n("flow_details.blacklisted_flow"),
   [14] = i18n("flow_details.flow_blocked_by_bridge"),
   [15] = i18n("flow_details.web_mining_detected"),
   [16] = i18n("flow_details.suspicious_device_protocol"),
   [17] = i18n("flow_details.elephant_flow_l2r"),
   [18] = i18n("flow_details.elephant_flow_r2l"),
   [19] = i18n("flow_details.longlived_flow"),
   [20] = i18n("flow_details.not_purged"),
   [21] = i18n("alerts_dashboard.ids_alert"),
   [22] = i18n("flow_details.tcp_severe_connection_issues"),
   [23] = i18n("flow_details.ssl_unsafe_ciphers"),
   [24] = i18n("flow_details.data_exfiltration"),
   [25] = i18n("flow_details.ssl_old_protocol_version"),
   }

   return entries
end



----------------------------------------------------------- -
utile per gli alert:

num_triggered_alerts table
num_triggered_alerts.min number 0
num_triggered_alerts.day number 0
num_triggered_alerts.hour number 0
num_triggered_alerts.5mins number 0

pezzo di tabella proveniente dalle stats di network_state.get_stats() dell'itratore egli host_ts

]]
