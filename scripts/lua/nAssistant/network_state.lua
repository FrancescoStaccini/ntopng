--
-- (C) 2019 - ntop.org
--
dirs = ntop.getDirs()
package.path = dirs.installdir .. "/scripts/lua/?.lua;" .. package.path
if((dirs.scriptdir ~= nil) and (dirs.scriptdir ~= "")) then package.path = dirs.scriptdir .. "/lua/modules/?.lua;" .. package.path 
elseif((dirs.scriptdir ~= nil) and (dirs.scriptdir ~= "")) then package.path = dirs.scriptdir .. "/lua/nAssistant/?.lua;" .. package.path end
require "lua_utils"

local network_state = {}
local if_stats = interface.getStats()


--------------------------------------------------------------------------------------------------------------
local deadline = 4 
local group_of = 10 

--[[ 
note: the caller can set the deadline

-"type"    is the type of entity to iterate over. Mandatory 
-"res"     table with the result, indexed by "name". Required if you want the result of the default callback
-"params"  array containing the name of the parameters of interest to the caller
]]
function network_state.get_stats( type, res, params, caller_deadline,  caller_callback) 
  local callback_utils = require "callback_utils"
  local ret = false

  --note: works only for "first level" structure, don't works for inner tables
  local function param_callback(name, stats) --note: This is the default callback
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

  if type == "flow" then 
    --note: for the flows in the callback -->  name = flow_key  &  stats = flow
    ret = callback_utils.foreachFlow(ifname, os.time() + custom_deadline, callback )
  elseif type == "devices" then 
    ret = callback_utils.foreachDevice(ifname, os.time() + custom_deadline, callback )
  elseif type == "host" then 
    ret = callback_utils.foreachHost(ifname, os.time() + custom_deadline, callback )
  elseif type == "localhost" then 
    ret = callback_utils.foreachLocalHost(ifname, os.time() + custom_deadline, callback )
  elseif type == "localhost_ts" then
       --note: for 'local rrd host', in the callback -->  stats = host_ts
    ret = callback_utils.foreachLocalRRDHost(ifname, os.time() + custom_deadline, true, callback )
  else
    ret = false
  end

  return ret
end

--##############################################################################################

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
--NOTE: here only for retrocompatibility
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
--NOTE: here only for retrocompatibility
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
--NOTE: here only for retrocompatibility
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
--NOTE: here only for retrocompatibility
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
--NOTE: here only for retrocompatibility
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
--NOTE: here only for retrocompatibility

function network_state.get_num_alerts_and_severity()
  require "alert_utils"
  local severity = {} --severity: (none,) info, warning, error

  local function severity_cont(alerts, severity_table )
      local severity_text = ""
    
      for i,v in pairs(alerts) do
        if v.alert_severity then 
          severity_text = alertSeverityLabel(v.alert_severity, true)
          severity_table[severity_text] = (severity_table[severity_text] or 0) + 1 
        end
      end
    end
    --------------------------------------------------------

  local engaged_alerts, past_alerts, flow_alerts, alerts_num = nil, nil, nil, 0

  if hasAlerts("engaged", getTabParameters(_GET, "engaged")) then 
      engaged_alerts = getAlerts("engaged", getTabParameters(_GET, "engaged"))
      alerts_num = alerts_num + #engaged_alerts
      severity_cont( engaged_alerts, severity)
  end

  if hasAlerts("historical", getTabParameters(_GET, "historical")) then 
      past_alerts = getAlerts("historical", getTabParameters(_GET, "historical"))
      alerts_num = alerts_num + #past_alerts
      severity_cont( past_alerts, severity)
  end

  if hasAlerts("historical-flows", getTabParameters(_GET, "historical-flows")) then
      past_flow_alerts = getAlerts("historical-flows", getTabParameters(_GET, "historical-flows"))
      alerts_num = alerts_num + #past_flow_alerts
      severity_cont( past_flow_alerts, severity)
  end

  return alerts_num, severity
end

--##############################################################################################
--NOTE: here only for retrocompatibility
function network_state.get_hosts_flow_alerts_stats()
  require "alert_utils"
  local flows = {} 

  local hosts_score = {}

  if hasAlerts("historical-flows", getTabParameters(_GET, "historical-flows")) then
    past_flow_alerts = getAlerts("historical-flows", getTabParameters(_GET, "historical-flows"))
    local alert_type, rowid, t_stamp, srv_addr, cli_addr, severity, alert_counter
    for _,v in pairs(past_flow_alerts) do 

      if v.alert_type       then alert_type = alertTypeLabel( v.alert_type, true )      else  alert_type      = "Unknown" end
      if v.rowid            then rowid  =  v.rowid                                      else  rowid           = "Unknown" end
      if v.alert_tstamp     then t_stamp =  os.date( "%c", tonumber(v.alert_tstamp))    else  t_stamp         = "Unknown" end
      if v.srv_addr         then srv_addr = v.srv_addr                                  else  srv_addr        = "Unknown" end
      if v.cli_addr         then cli_addr = v.cli_addr                                  else  cli_addr        = "Unknown" end
      if v.alert_severity   then severity = alertSeverityLabel(v.alert_severity, true)  else  severity        = "Unknown" end
      if v.alert_counter    then alert_counter = tonumber(v.alert_counter)              else  alert_counter   = 0         end
      
      local e = {
        id           = rowid,
        type         = alert_type,
        tstamp       = t_stamp,
        severity     = severity,
        srv_addr     = srv_addr,
        cli_addr     = cli_addr,
        alert_counter= alert_counter
      }

      if hosts_score[srv_addr] then 
        hosts_score[srv_addr].alert_counter = hosts_score[srv_addr].alert_counter + alert_counter
        hosts_score[srv_addr].tot_flows_bytes = hosts_score[srv_addr].tot_flows_bytes + v.srv2cli_bytes + v.cli2srv_bytes
        hosts_score[srv_addr].severity[severity] = hosts_score[srv_addr].severity[severity] + alert_counter
      else 
        hosts_score[srv_addr] = {
          alert_counter = alert_counter,
          tot_flows_bytes = v.srv2cli_bytes + v.cli2srv_bytes,
          severity = {
            Error = 0,
            Warning = 0,
            Info = 0 }
        }
        hosts_score[srv_addr].severity[severity] = hosts_score[srv_addr].severity[severity] + alert_counter
      end
      if hosts_score[cli_addr] then
        hosts_score[cli_addr].alert_counter = hosts_score[cli_addr].alert_counter + alert_counter
        hosts_score[cli_addr].tot_flows_bytes = hosts_score[cli_addr].tot_flows_bytes + v.srv2cli_bytes + v.cli2srv_bytes
        
        hosts_score[cli_addr].severity[severity] = hosts_score[cli_addr].severity[severity] + alert_counter
      else
        hosts_score[cli_addr] = {
          alert_counter = alert_counter,
          tot_flows_bytes = v.srv2cli_bytes + v.cli2srv_bytes,
          severity = {
            Error = 0,
            Warning = 0,
            Info = 0 }
        }
        hosts_score[cli_addr].severity[severity] = hosts_score[cli_addr].severity[severity] + alert_counter
      end
    end
  end

  local tmp ={}
  for i,v in pairs(hosts_score) do
    table.insert(tmp, table.merge(v,{addr= i}) )
  end
  local function compare(a, b) return a.alert_counter > b.alert_counter end
  table.sort( tmp, compare )
  hosts_score = tmp

  return hosts_score
end

--##############################################################################################

function network_state.get_hosts_flow_misbehaving_stats()
  local flow_consts = require "flow_consts"
  local res = {}

  local function misbehaving_flows(name, stats)
      local tmp = {}
      if not res then return false end

      if stats["flow.status"] ~= 0 --[[status_normal]] then
        table.insert(res, stats)
      end
      return true
  end
  network_state.get_stats("flow",res,nil,nil, misbehaving_flows)

  local flow_status_relevance_map = {} 
  local j = 1

  for _ in pairs(flow_consts.status_types) do
    flow_status_relevance_map[j] = 0
    j= j+1
  end
  for _,v in pairs(flow_consts.status_types) do 
    flow_status_relevance_map[v.status_id] = v.relevance
  end

  local hosts_score = {}
  for i,v in pairs(res) do
    local cli_addr, srv_addr, status = v["cli.ip"], v["srv.ip"], v["flow.status"]

    if hosts_score[cli_addr] then
      hosts_score[cli_addr].flow_counter = hosts_score[cli_addr].flow_counter + 1
      hosts_score[cli_addr].tot_flows_bytes = hosts_score[cli_addr].tot_flows_bytes + v.bytes
      hosts_score[cli_addr].score = hosts_score[cli_addr].score + flow_status_relevance_map[status]
      if hosts_score[cli_addr].status[status ] then 
        hosts_score[cli_addr].status[ status ] = hosts_score[cli_addr].status[ status ] +1
      else 
        hosts_score[cli_addr].status[ status ] = 1
      end
    else
      hosts_score[cli_addr] = {
        flow_counter = 1,
        tot_flows_bytes = v.bytes,
        status= {},
        score = flow_status_relevance_map[status]
      }
      hosts_score[cli_addr].status[status] = 1
    end
    if hosts_score[srv_addr] then
      hosts_score[srv_addr].flow_counter = hosts_score[srv_addr].flow_counter + 1
      hosts_score[srv_addr].tot_flows_bytes = hosts_score[srv_addr].tot_flows_bytes + v.bytes
      hosts_score[srv_addr].score = hosts_score[srv_addr].score + flow_status_relevance_map[status]

      if hosts_score[srv_addr].status[ status ] then 
        hosts_score[srv_addr].status[ status ] = hosts_score[srv_addr].status[ status ] +1
      else 
        hosts_score[srv_addr].status[ status ] = 1
      end
    else
      hosts_score[srv_addr] = {
        flow_counter = 1,
        tot_flows_bytes = v.bytes,
        status = { },
        score = flow_status_relevance_map[status]
      }
      hosts_score[srv_addr].status[status] = 1
    end
  end
  --NOTE:  score ==> ( #misbehaving flows * "relevance" )
  local tmp ={}
  for i,v in pairs(hosts_score) do
    table.insert(tmp, table.merge(v,{addr= i}) )
  end
  local function compare(a, b) return a.score > b.score end
  table.sort( tmp, compare )
  hosts_score = table.clone(tmp)

  return hosts_score
end

--##############################################################################################

--return table with entry like [ghost domain name - hits ]
function network_state.get_interface_ghost_network()
  local res = {}

  local stats, g_dom = interface.getStats(), {}
  if stats and stats.bcast_domains then 
    for domain_name, domain_info in pairs(stats.bcast_domains) do
      if domain_info.ghost_network == "true" then 
        res[domain_name] = domain_info.hits
      end
    end
  end

  return res
end

------------------------------------------------------------------------------------------------
--##############################################################################################

return network_state