--
-- (C) 2019 - ntop.org
--
dirs = ntop.getDirs()
package.path = dirs.installdir .. "/scripts/lua/?.lua;" .. package.path
if((dirs.scriptdir ~= nil) and (dirs.scriptdir ~= "")) then package.path = dirs.scriptdir .. "/lua/modules/?.lua;" .. package.path end

require "lua_utils"
local dialogflow = require "nAssistant/dialogflow_APIv2"
local net_state = require "nAssistant/network_state"
local df_utils = require "nAssistant/dialogflow_utils" 

--+++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
--#################################### - Handlers - Utils - ###############################################
--+++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
local h_utils = {}

--ABOUT: traffic volume, in/out, TCP efficiency
function h_utils.get_aggregated_info_traffic()
  local stats, text = net_state.check_net_communication(),""
  local ctg, prc = net_state.check_top_traffic_application_protocol_categories()

  if stats.prc_remote2local_traffic + stats.prc_local2remote_traffic < 50 then
    text = text .. "Traffic is mainly internal to the network "
  elseif stats.prc_remote2local_traffic > stats.prc_local2remote_traffic then 
    text = text .. "Most of the data traffic comes from outside the network, "
  else 
    text = text .. "Traffic is mostly directed outside of the network, "
  end

  text = text .. " of which "..prc.." % is "..ctg..". Data transmission efficiency is "
 
  local state, perc = "", net_state.get_aggregated_TCP_flow_goodput_percentage()
  
  if perc > 90 then 
      state = "overall excellent" 
    elseif perc > 80 then 
      state = "overall good"
    elseif perc > 70 then
      state = "overall mediocre"
    else 
      state = "overall low" 
    end

  return text..state.."."
end

--#########################################################################################################
--note: for retrocompatibility
function h_utils.get_aggregated_info_devices()
  local info, devices_num = net_state.check_devices_type()
  local text2 = ""
  
  text = "I detect "..  devices_num.. " devices connected. "

  for i,v in pairs(info) do
    if i ~= "Unknown" then text2 = text2 .. v.. " ".. i.. ", " end
  end

  if text2 ~= "" then 
    text =  text .. "Including ".. text2
  end

  return text
end

--#########################################################################################################
--note: for retrocompatibility
function h_utils.are_app_and_hosts_good()
  local ndpi_breeds, blacklisted_host_num, danger  = net_state.check_bad_hosts_and_app()
  local prc_safe = ndpi_breeds["Safe"] or 0 
  local safe_text, score, text = "", 0, ""

  if ndpi_breeds == nil then
    return ""
  end

  if ndpi_breeds["Safe"] then
    score = score + ( ndpi_breeds["Safe"]["perc"] or 0 )
  end

  if ndpi_breeds["Fun"] then
    score = score + ( (ndpi_breeds["Fun"]["perc"] or 0) * 0.85 )
  end
  if ndpi_breeds["Acceptable"] then
    score = score + ( (ndpi_breeds["Acceptable"]["perc"] or 0) * 0.8 )
  end

  if score >= 99 then 
    safe_text = ", in general, are safe"
  elseif score >= 90 then
    safe_text = "are mostly safe"
  elseif score >= 75 then
    safe_text = "are quite safe"
  elseif score >= 50 then
    safe_text = "are only partially safe "
  elseif score >= 25 then
    safe_text = "are poorly safe"
  else 
    safe_text = "are potentially dangerous"
  end

  local bl_num_txt = ""
  if blacklisted_host_num == 0 then
    bl_num_txt = "No unwanted hosts.\n"
  elseif blacklisted_host_num == 1 then
    bl_num_txt = "One unwanted host.\n"
  else 
    bl_num_txt = blacklisted_host_num .. " unwanted hosts.\n"
  end

  text = bl_num_txt .. " The communications "..safe_text

  if danger then text = text .. ". \nBut be careful! Dangerous traffic has been detected! " end

  return text
end
  
--#########################################################################################################

--ABOUT: security stuff: alert triggered, bad host, traffic breed
function h_utils.get_aggregated_info_network()
  local stats = net_state.check_ifstats_table()
  local alert_num, severity = net_state.get_num_alerts_and_severity()
  local alert_text = ""

  if alert and alert_num > 0 then
    alert_text = alert_num .. " alerts triggered, of which "

    for i,v in pairs(severity) do
      if v > 0 then  alert_text = alert_text .. v .. " " .. i .. ", " end
    end
    alert_text = string.sub(alert_text,1,-2)
    alert_text = string.sub(alert_text,1,-2)
    alert_text = alert_text..".\n"

  else
    alert_text = "0 alerts triggered\n"
  end

  local app_host_good_text, b, danger = are_app_and_hosts_good() --TODO: "b" a che serve? rimuovila in caso
  local text = alert_text.. app_host_good_text

  return text
end

--ABOUT: summary of the others topic
--#########################################################################################################
function h_utils.get_aggregated_info_generic()
  local stats = net_state.check_ifstats_table()
  local alert_num, severity = net_state.get_num_alerts_and_severity()
  local top_apps = net_state.check_top_application_protocol()
  local top_category = net_state.check_traffic_categories()
  local alert_text = ""

  if alert_num and alert_num > 0 then
    alert_text = alert_num .. " alerts triggered, "
  else
    alert_text = "0 alerts triggered, \n"
  end

  local app_host_good_text, b, danger = are_app_and_hosts_good()
  local text = "I notice:\n"..stats.device_num.." devices connected, "..stats.flow_num.." active communications.\n"

  if top_category and top_category[1] then 
    text = text .. " Traffic is mostly ".. top_category[1].name .. ", "
  end

  if top_apps and top_apps[1] then 
    text = text .. " and the most talky application is ".. top_apps[1].name..".\n"
  end
  text = text .. alert_text.. app_host_good_text

  return text
end

--#########################################################################################################
--note: for retrocompatibility
--return: a table with every host(IP and name) for a specific MAC
function h_utils.find_mac_hosts(name) 

  local hosts_names = interface.findHost(name) --it search "names" among (and inside) all the host names
  if not hosts_names then return 0, nil end

  local macs_table, tmp_host_info, tmp_mac_info = {}, {}, {}

  for i,v in pairs(hosts_names) do--"i" contiene gli ip, "v" contiene il nome (può essere mac, alias o ip)
    tmp_host_info = interface.getHostInfo(i)

    if tmp_host_info then
      if not macs_table[tmp_host_info.mac] then macs_table[tmp_host_info.mac] = {} end
      table.insert(macs_table[tmp_host_info.mac], {ip = i, name = tmp_host_info.name} )
      --macs_table[tmp_host_info.mac] = { name = getHostAltName( tmp_host_info.mac ) } 
    end
  end

  if macs_table then 
    return table.len(macs_table), macs_table, tmp_host_info.mac
  else
    return 0, nil
  end

end
--#########################################################################################################
--note: for retrocompatibility
function h_utils.find_device_name_and_addresses(query)

  local max_total_items = 8
  local results = {}

  if(query == nil) then query = "" end

  interface.select(ifname)

  -- Hosts
  local res = interface.findHost(query)
  --findHost restituirsce la tabella con entry fatte--> [ IP - mac ]

  -- Also look at the custom names
  local ip_to_name = ntop.getHashAllCache(getHostAltNamesKey()) or {}
  for ip,name in pairs(ip_to_name) do
    if string.contains(string.lower(name), string.lower(query)) then
        res[ip] = hostVisualization(ip, name)     --note: hostVisualization(...) put "[IPv6]" for ipv6 hosts
    end
  end

  local ips = {}
  local info_host_by_mac = nil
  local num_items = 0
  for k, v in pairs(res) do
    if num_items >= max_total_items then break end

    if v ~= "" then
      if isIPv6(v) and (not string.contains(v, "%[IPv6%]")) then
        v = v.." [IPv6]"
      end

      if isMacAddress(v) then         --case v = k
        info_host_by_mac = interface.findHostByMac(v)
        for _,vv in pairs(info_host_by_mac) do
          table.insert(ips,vv)
        end

        results[v] = {name = v, ip = ips}
        num_items = num_items + 1 

      elseif isMacAddress(k) then     --case: mac is the key

        info_host_by_mac = interface.findHostByMac(k)
        for _,vv in pairs(info_host_by_mac) do
          table.insert(ips,vv)
        end
        results[k] = {name = v, ip = ips}
        num_items = num_items + 1 
      else                            --case: k = ip, v = name

        local h_info = interface.getHostInfo(k)
        if h_info then
          info_host_by_mac = interface.findHostByMac(h_info["mac"])

          for _,vv in pairs(info_host_by_mac) do
            table.insert(ips,vv)
          end
          results[h_info["mac"]] = {name = v, ip = ips}
          num_items = num_items + 1 
        end

      end
      ips = {}

    end 
  end--\for

  return results, num_items

end

--#########################################################################################################
--note: for retrocompatibility
--return info about a device and it's hosts
function h_utils.merge_hosts_info(ip_table)
  local res = nil
  local ndpi_categories_tot_bytes, ndpi_tot_bytes = 0, 0

  for _,ip in ipairs(ip_table) do   
    --[[TODO: controlla se il num di bytes torna con le ndpi app e coi i bytes inviai/ricevuti su getMAc/HostInfo(..) )   )
        TODO: le varie info per stabilire se la connessione è buona. aspetto che tale lavoro (anche se aggregato) venga fatto su network_state perché
          sono state introdotte nuove info da controllare e c'è da rifare roba  ]]

    local host_info = interface.getHostInfo(ip)

    if res == nil then --tabella vuota, popolo con le info che sono uguali per ogni host del device, lo faccio solo la prima volta
      --attualmente tengo più info di quante ne uso:
      --TODO:(salta http - sites - dns che li vedrei solo della macchina dove gira ntopng, però i contatori dei metodi hhtp funzionano ugualmente)
      --la tabella di ndpi_categories e ndpi, tutta. dagli host
      
      res = host_info 
      local mac_info = interface.getMacInfo(host_info.mac)

      local discover = require "discover_utils"
      if host_info.devtype and host_info.devtype ~= 0 then 
         
        res["devtype_name"] = discover.devtype2string(host_info.devtype) 
      else 
        res["devtype_name"]  = "Unknown"
      end
      res["num_blacklisted_host"] = ternary( host_info.is_blacklisted, 1, 0 )
      res["num_childSafe_host"] = ternary( host_info.childSafe, 1, 0 )
      res["manufacturer"] = ternary( mac_info and mac_info.manufacturer, mac_info.manufacturer, "Unknown"  )
      res["model"] = ternary( mac_info and mac_info.model, mac_info.model, "Unknown"  )
      res["operatingSystem"] = ternary( mac_info and mac_info.operatingSystem ~= 0, discover.getOsName(mac_info.operatingSystem), "Unknown"  ) --Test in progress
      --TODO: first_seen/last_seen guardalo da mac_details (ed il First Observed On??)

    else --qui faccio i merge
      ------ndpi_categories------
      for name, info in pairs(host_info.ndpi_categories) do
        if res.ndpi_categories[name] then --esiste già in res (aggiorno solo le info che incrementano)
          res.ndpi_categories[name].bytes           = res.ndpi_categories[name].bytes + info.bytes
          res.ndpi_categories[name]["bytes.rcvd"]   = res.ndpi_categories[name]["bytes.rcvd"] + info["bytes.rcvd"]
          res.ndpi_categories[name]["bytes.sent"]   = res.ndpi_categories[name]["bytes.sent"] + info["bytes.sent"]
          res.ndpi_categories[name].duration        = res.ndpi_categories[name].duration + info.duration
        else--prima volta che lo vedo
          res.ndpi_categories[name] = info
        end
        ndpi_categories_tot_bytes = ndpi_categories_tot_bytes + info.bytes
      end
      ------ndpi------
      for name, info in pairs(host_info.ndpi) do
        if res.ndpi[name] then --esiste già in res (aggiorno solo le info che incrementano)
          res.ndpi[name]["bytes.rcvd"]          = res.ndpi[name]["bytes.rcvd"] + info["bytes.rcvd"]
          res.ndpi[name]["bytes.sent"]          = res.ndpi[name]["bytes.sent"] + info["bytes.sent"]
          res.ndpi[name].duration               = res.ndpi[name].duration + info.duration 
          --faccio il totale delle duration, però non tengo conto che potebbero sovrapporsi temporalmente. (ma capita davvero che si sovrappongono? beh dipende dall'app!)
        else--prima volta che lo vedo
          res.ndpi[name] = info
        end
        ndpi_tot_bytes = ndpi_tot_bytes + info["bytes.sent"]  + info["bytes.rcvd"] 
      end
      -------alerts--------
      if host_info.is_blacklisted then res["num_blacklisted_host"] = res["num_blacklisted_host"] + 1 end --TODO: test
      if host_info.childSafe then res["num_childSafe_host"] = res["num_childSafe_host"] + 1 end --TODO: test
       --TODO: ma num_aletrs si riferisce all'host, farne la somma non credo abbia senso
       --non sono molto convinto degli alert
      res["num_alerts"] = res["num_alerts"] + host_info["num_alerts"]
      res["total_alerts"] = res["total_alerts"] + host_info["total_alerts"]

      --note faccio ciò per togliere il tag [...] a seguito del nome ( es. nome & nome [IPv6] )
      if host_info.name and ( string.len(res.name) > string.len(host_info.name) ) then res.name = host_info.name end

    end
  end--end-for

  --ordino ndpi app e categories
  local tmp = {}
  if res and res.ndpi then 
    for i,v in pairs(res.ndpi) do
      table.insert(tmp, {name = i, info = v, percentage = math.floor( ( (v["bytes.rcvd"] + v["bytes.sent"]) / ndpi_tot_bytes) * 100 ) } )
    end
    table.sort(tmp, function (a,b) return ( a.info["bytes.rcvd"] + a.info["bytes.sent"] ) > (b.info["bytes.sent"] + b.info["bytes.rcvd"]) end)
    res.ndpi = tmp
  end

  tmp = {}
  if res and res.ndpi_categories then 
    for i,v in pairs(res.ndpi_categories) do
      table.insert(tmp, {name = i, info = v, percentage = math.floor( (v.bytes / ndpi_categories_tot_bytes) * 100 ) } )
    end
    table.sort(tmp, function (a,b) return a.info.bytes > b.info.bytes end)
    res.ndpi_categories = tmp
  end

  --TODO: fai bene, questa soluzione è temporanea!
  if (res.name == nil or res.name == "") and res.names and res.names.dhcp then 
    res.name =  res.names.dhcp
  end

  return res
end

--#########################################################################################################

 return h_utils