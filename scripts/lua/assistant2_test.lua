--
-- (C) 2019 - ntop.org
--
dirs = ntop.getDirs()
package.path = dirs.installdir .. "/scripts/lua/?.lua;" .. package.path
if((dirs.scriptdir ~= nil) and (dirs.scriptdir ~= "")) then package.path = dirs.scriptdir .. "/lua/modules/?.lua;" .. package.path end
ignore_post_payload_parse = 1

require "lua_utils"
local dialogflow = require "dialogflow_APIv2"
local net_state = require "network_state"

--TODO: poi spostali
local df_utils = require("dialogflow_utils") --

local response, request

--TODO: CANCELLA I VECCHI FILE: google_assistant_utils.lua ecc.
--      sistema l'inglese
--      AGGIUNGI I SUGGERIMENTI 
--      telegram bot: guarda se, a posteriori dell'apertura della chat da parte dell'utente, è possibile prendersi il chatID (e il token come lo piglio? hardcoded? ma è pubblico il codice!)

--##########################################-nAssistant-utils-############################################################

local function get_aggregated_info_traffic()
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


local function get_aggregated_info_devices()
  local info, devices_num = net_state.check_devices_type()
  local text2 = ""
  
  text = "I detect "..  devices_num.. " devices connected. "

  for i,v in pairs(info) do
    if i ~= "Unknown" then text2 = text2 .. v.. " ".. i.. ", " end
  end

  if text2 ~= "" then 
    text =  text .. "Including ".. text2
  end

  --text = text .. ". Vuoi informazioni più dettagliate? Altrimenti dimmi il nome, o l'indirizzo, di un dispositivo"
  return text
end

--#########################################################################################################

local function are_app_and_hosts_good()
  local ndpi_breeds, blacklisted_host_num, danger  = net_state.check_bad_hosts_and_app()
  local prc_safe = ndpi_breeds["Safe"] or 0 
  local safe_text, score, text = "", 0, ""

  if ndpi_breeds == nil then
    --TODO:rifai, è pericoloso perché viene utilizzato anche per comporre frasi!
    --google.send("Non sono riuscito ad eseguire la richiesta") 
    return ""
    --credo sia meglio ritornare stringa vuota, fai i test! (tipo vedi la handler_network_state())
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

  --score = ( ndpi_breeds["Safe"]["perc"] or 0 )  +  ( (ndpi_breeds["Fun"]["perc"] or 0) * 0.85 )  +  ( (ndpi_breeds["Acceptable"]["perc"] or 0) * 0.8 )

  --TODO: ripensa a modo le soglie del safe score
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

  text = bl_num_txt .. " The communication "..safe_text

  if danger then text = text .. ". \nBut be careful! Dangerous traffic has been detected! " end

  return text
end
  
--#########################################################################################################

local function et_aggregated_info_network()
  local stats = net_state.check_ifstats_table()
  local alert_num, severity = net_state.get_num_alerts_and_severity()
  local alert_text = ""

  if alert_num > 0 then
    alert_text = alert_num .. " alarms triggered, of which "

    for i,v in pairs(severity) do
      if v > 0 then  alert_text = alert_text .. v .. " " .. i .. ", " end
    end

    alert_text = string.sub(alert_text,1,-2)
    alert_text = string.sub(alert_text,1,-2)
    alert_text = alert_text..".\n"

  else
    alert_text = "0 alarm triggered\n"
  end

  local app_host_good_text, b, danger = are_app_and_hosts_good() --TODO: "b" a che serve? rimuovila in caso

  local text = alert_text.. app_host_good_text

  -- local sugg = {}
  -- if danger and alert_num > 0 then 
  --   sugg = {"traffico pericoloso", "allarmi attivi"}
  -- elseif danger and alert_num == 0  then
  --   sugg = {"traffico pericoloso"}
  -- elseif not danger and alert_num > 0   then
  --   sugg = {"allarmi attivi"}
  -- else --not danger and alert_num == 0
  --   sugg = {}
  -- end

  return text
end

--#########################################################################################################
function get_aggregated_info_generic()
  local stats = net_state.check_ifstats_table()
  local alert_num, severity = net_state.get_num_alerts_and_severity()
  local top_apps = net_state.check_top_application_protocol()
  local top_category = net_state.check_traffic_categories()
  local alert_text = ""

  if alert_num > 0 then
    alert_text = alert_num .. " alarms triggered, "
  else
    alert_text = "0 alarms triggered, \n"
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

--########################################-END-nAssistant-utils-##################################################
------------------------------------------------------------------------------------------------------------------
--##############################################-Handlers-########################################################


--TODO: RICH MESSAGE!!!! [ https://cloud.dialogflow.com/dialogflow/docs/intents-rich-messages ] inoltre esempi json tra i preferiti
--idea: nell'URL dell'immagine metto il link al(lo scriptino lua nel) server ntop con alla fine i parametri 
--      necessari per fare il grafico




--return an overview of the top ndpi_application regarding the active flows
function handler_if_active_flow_top_application()
    local top_app = net_state.check_top_application_protocol() --TODO: sistema
    --note: top app is in decrescent order and contain, for each proto, [name-percent-bytes]
    if not top_app then 
        dialogflow.send("I have not found any active communication! Please try again later")
        return
    end
    local labels, values, datasets = {},{},{}
    local legend_label = "Traffic (KB)"
    local data = {labels = {}, values = {}, legend_label = legend_label}
    local options = { 
        w = "600",
        h = "280",
        chart_type = "bar",
        bkg_color = "white"
    }
    local i = 0
    for _,v in ipairs(top_app) do
        table.insert(data.labels, v.name)
        table.insert(data.values, v.bytes/1024 ) --TODO: se necessario (tanto traffico) metti i MB invece dei KB
        i = i + 1
        if i >= 6 or v.percentage < 1 then break end    --NOTE: 6 and 1 are arbitrary
    end

    local url = df_utils.create_chart_url(data, options)
    local card = dialogflow.create_card(
        "Top Application Chart",
        url,
        "Top Application Chart"
    )
    local speech_text = df_utils.create_top_traffic_speech_text(top_app)
    local display_text = "Here is the chart"

    dialogflow.send(speech_text, display_text, nil, nil, card)
end


function handler_get_aggregated_info()
  local response_text = ""
  local tips = {}

  --prendo i param per vedere se è Devices, Network, Traffic, Generic
  local aggregator = request.parameters.Aggregators

  --gestisco i 4 differenti casi
  if aggregator == "Generic" then --mega overview
      response_text = get_aggregated_info_generic()

  elseif aggregator == "Traffic" then --traffic / communication
      response_text = get_aggregated_info_traffic()

  elseif aggregator == "Network" then -- security (bad host, dangerous flow)/ alarm 
      response_text = get_aggregated_info_network()

  elseif aggregator == "Devices" then --devices/hosts
      response_text = get_aggregated_info_devices()
  
  else
       --[[fallback]]
       --non credo ci sia bisogno di implementare una fallback apposita per aggregated_info
       dialogflow.send("Ops! I've a problem, please contact ntopng maintainers")--TODO fai un messaggio di errore a modo con link esterno verso una issue di github
  end

  dialogflow.send(response_text)
end

--WIP
function handler_get_aggregated_info_more()
  -- local response_text = ""
  -- local tips = {}

  -- local aggregator = request.parameters.Aggregators

  -- if aggregator == "Generic" then 
  --     response_text = get_aggregated_info_generic()

  -- elseif aggregator == "Traffic" then 
  --     response_text = get_aggregated_info_traffic()

  -- elseif aggregator == "Network" then 
  --     response_text = get_aggregated_info_network()

  -- elseif aggregator == "Devices" then 
  --     response_text = get_aggregated_info_devices()
  -- else
  --      --[[fallback]]
  --      --non credo ci sia bisogno di implementare una fallback apposita per "aggregated_info - more"
  -- end

  dialogflow.send(response_text)
end

-- WIP+-
function handler_if_active_flow_top_categories()
  local top_cat = net_state.check_traffic_categories()
  --note: top app is in decrescent order and contain, for each caregory, [name-perc-bytes]
  if not top_cat then 
      dialogflow.send("I have not found any active communication! Please try again later")
      return
  end
  local labels, values, datasets = {},{},{}
  local legend_label = "Traffic (KB)"
  local data = {labels = {}, values = {}, legend_label = legend_label}
  local options = { 
      w = "600",
      h = "280",
      chart_type = "bar",
      bkg_color = "white"
  }
  local i = 0
  for _,v in ipairs(top_cat) do
      table.insert(data.labels, v.name)
      table.insert(data.values, v.bytes/1024 ) --TODO: se necessario (tanto traffico) metti i MB invece dei KB
      i = i + 1
      if i >= 6 or v.perc < 1 then break end    --NOTE: 6 and 1 are arbitrary
  end

  local url = df_utils.create_chart_url(data, options)
  local card = dialogflow.create_card(
      "Top Categories Chart",
      url,
      "Top Categories Chart"
  )
  --local speech_text = df_utils.create_top_categories_speech_text(top_cat)
  local display_text = "Here is the chart"

  --dialogflow.send(speech_text, display_text, nil, nil, card)
  dialogflow.send(display_text, nil, nil, nil, card)
end


--WIP
--todo: SISTEMA NOMI, METTILI IN UN GRAFICO, (E SE MIGLIORI LE PREFORMANCE ALLORA TOP, faccio una marea di iterazioni sugli host/devices)
function handler_who_are_categories()
  --TODO: cicla tra host/dispositivi per vedere CHI appartiene a tale categoria

  local category = request.parameters.ndpi_category
  local tmp, res, byte_tot = {}, {}. 0

  ----------------------------------------------------
  local function get_stats_callback(mac, stats)

    local function find_name(mac)
      local name,host = nil,nil

      local t = interface.findHostByMac(mac)

      if t then 

        for i,v in pairs(t) do
          host = interface.getHostInfo(i)
          if host then 
            name = host.name
            break
          end
        end

      end
      return ternary( name ~= nil and name ~= "", name, mac)
    end

    if stats["ndpi_categories"] and stats["ndpi_categories"][category] and stats["ndpi_categories"][category]["bytes"]then 
        table.insert(tmp, {
          bytes = stats["ndpi_categories"][category]["bytes"],
          manufacturer = stats.manufacturer,
          name = find_name(mac)
      })
      byte_tot = byte_tot + stats["ndpi_categories"][category]["bytes"]
    end
  end
  -----------------------------------------------------
  net_state.get_stats("devices", nil, nil, nil, get_stats_callback)
  


  -- local labels, values, datasets = {},{},{}
  -- local legend_label = "Traffic (KB)"
  -- local data = {labels = {}, values = {}, legend_label = legend_label}
  -- local options = { 
  --     w = "600",
  --     h = "280",
  --     chart_type = "bar",
  --     bkg_color = "white"
  -- }
  -- local i = 0
  -- for _,v in ipairs(tmp) do
  --     table.insert(data.labels, v.name)
  --     table.insert(data.values, v.bytes/1024 ) --TODO: se necessario (tanto traffico) metti i MB invece dei KB
  --     i = i + 1
  --     if i >= 6 or v.perc < 1 then break end    --NOTE: 6 and 1 are arbitrary
  -- end

  -- local url = df_utils.create_chart_url(data, options)
  -- local card = dialogflow.create_card(
  --     "Top Categories Chart",
  --     url,
  --     "Top Categories Chart"
  -- )
  -- --local speech_text = df_utils.create_top_categories_speech_text(top_cat)
  -- local display_text = "Here is the chart"

  -- --dialogflow.send(speech_text, display_text, nil, nil, card)
  -- dialogflow.send(display_text, nil, nil, nil, card)


  tprint(tmp)
  --[[
esempio di tmp:

 table
10:65:30:08:97:08 table
10:65:30:08:97:08.name string kilian-IIT
10:65:30:08:97:08.manufacturer string Dell Inc.
10:65:30:08:97:08.bytes number 960
00:0C:29:60:74:90 table
00:0C:29:60:74:90.name string 00:0C:29:60:74:90
00:0C:29:60:74:90.manufacturer string VMware, Inc.
00:0C:29:60:74:90.bytes number 17981
D8:18:D3:78:C6:2F table
D8:18:D3:78:C6:2F.name string 2a00:1450:400c:c06::9a
D8:18:D3:78:C6:2F.manufacturer string Juniper Networks
D8:18:D3:78:C6:2F.bytes number 241880
00:0C:29:23:26:D5 table
00:0C:29:23:26:D5.name string 00:0C:29:23:26:D5
00:0C:29:23:26:D5.manufacturer string VMware, Inc.
00:0C:29:23:26:D5.bytes number 4080
00:00:5E:00:02:60 table
00:00:5E:00:02:60.name string fe80::fd:60:0:0
00:00:5E:00:02:60.manufacturer string ICANN, IANA Department
00:00:5E:00:02:60.bytes number 222409
00:22:15:03:C2:F4 table
00:22:15:03:C2:F4.name string 00:22:15:03:C2:F4
00:22:15:03:C2:F4.manufacturer string ASUSTek COMPUTER INC.
00:22:15:03:C2:F4.bytes number 389
18:60:24:8D:01:F8 table
18:60:24:8D:01:F8.name string DESKTOP-67PRDJH
18:60:24:8D:01:F8.manufacturer string Hewlett Packard
18:60:24:8D:01:F8.bytes number 1137419
18:60:24:7B:EB:39 table
18:60:24:7B:EB:39.name string DESKTOP-7PGI4EI
18:60:24:7B:EB:39.manufacturer string Hewlett Packard
18:60:24:7B:EB:39.bytes number 311070
C4:54:44:23:E4:2B table
C4:54:44:23:E4:2B.name string wafivm5.iit.cnr.it
C4:54:44:23:E4:2B.manufacturer string Quanta Computer Inc.
C4:54:44:23:E4:2B.bytes number 3554
A4:BA:DB:41:A6:C5 table
A4:BA:DB:41:A6:C5.name string wafivm4.iit.cnr.it
A4:BA:DB:41:A6:C5.manufacturer string Dell Inc.
A4:BA:DB:41:A6:C5.bytes number 3551
A0:CE:C8:11:3A:6A table
A0:CE:C8:11:3A:6A.name string MBP-di-Matteo
A0:CE:C8:11:3A:6A.manufacturer string Ce Link Limited
A0:CE:C8:11:3A:6A.bytes number 868
14:18:77:53:49:98 table
14:18:77:53:49:98.name string 14:18:77:53:49:98
14:18:77:53:49:98.manufacturer string Dell Inc.
14:18:77:53:49:98.bytes number 13376
00:00:5E:00:01:60 table
00:00:5E:00:01:60.name string 00:00:5E:00:01:60
00:00:5E:00:01:60.manufacturer string ICANN, IANA Department
00:00:5E:00:01:60.bytes number 158178
AC:9E:17:81:A1:76 table
AC:9E:17:81:A1:76.name string AC:9E:17:81:A1:76
AC:9E:17:81:A1:76.manufacturer string ASUSTek COMPUTER INC.
AC:9E:17:81:A1:76.bytes number 2849993
C0:33:5E:72:90:5E table
C0:33:5E:72:90:5E.name string nuvirin
C0:33:5E:72:90:5E.manufacturer string Microsoft
C0:33:5E:72:90:5E.bytes number 58604
54:04:A6:70:46:94 table
54:04:A6:70:46:94.name string 54:04:A6:70:46:94
54:04:A6:70:46:94.manufacturer string ASUSTek COMPUTER INC.
54:04:A6:70:46:94.bytes number 2907
90:1B:0E:99:23:94 table
90:1B:0E:99:23:94.name string wafivm7.iit.cnr.it
90:1B:0E:99:23:94.manufacturer string Fujitsu Technology Solutions GmbH
90:1B:0E:99:23:94.bytes number 3164
D8:18:D3:78:CB:2F table
D8:18:D3:78:CB:2F.name string D8:18:D3:78:CB:2F
D8:18:D3:78:CB:2F.manufacturer string Juniper Networks
D8:18:D3:78:CB:2F.bytes number 2228939
BC:AE:C5:27:8F:B7 table
BC:AE:C5:27:8F:B7.name string djackcnr
BC:AE:C5:27:8F:B7.manufacturer string ASUSTek COMPUTER INC.
BC:AE:C5:27:8F:B7.bytes number 7849
40:A8:F0:22:A0:60 table
40:A8:F0:22:A0:60.name string fe80::42a8:f0ff:fe22:a060
40:A8:F0:22:A0:60.manufacturer string Hewlett Packard
40:A8:F0:22:A0:60.bytes number 498
9C:93:4E:60:19:44 table
9C:93:4E:60:19:44.name string 9C:93:4E:60:19:44
9C:93:4E:60:19:44.manufacturer string Xerox Corporation
9C:93:4E:60:19:44.bytes number 3747
00:0E:C6:C7:F5:AD table
00:0E:C6:C7:F5:AD.name string MBP-di-Maurizio
00:0E:C6:C7:F5:AD.manufacturer string Asix Electronics Corp.
00:0E:C6:C7:F5:AD.bytes number 7960
00:19:BB:46:60:DF table
00:19:BB:46:60:DF.name string dhcp84.iit.cnr.it
00:19:BB:46:60:DF.manufacturer string Hewlett Packard
00:19:BB:46:60:DF.bytes number 1596
48:2A:E3:05:F5:78 table
48:2A:E3:05:F5:78.name string 48:2A:E3:05:F5:78
48:2A:E3:05:F5:78.manufacturer string Wistron InfoComm(Kunshan)Co.,Ltd.
48:2A:E3:05:F5:78.bytes number 85
C8:1F:66:BE:33:F4 table
C8:1F:66:BE:33:F4.name string confmaster.iit.cnr.it
C8:1F:66:BE:33:F4.manufacturer string Dell Inc.
C8:1F:66:BE:33:F4.bytes number 32176
52:54:00:7F:72:83 table
52:54:00:7F:72:83.name string 52:54:00:7F:72:83
52:54:00:7F:72:83.manufacturer string Realtek (UpTech? also reported)
52:54:00:7F:72:83.bytes number 374
38:D5:47:32:2D:FE table
38:D5:47:32:2D:FE.name string DESKTOP-38KKIFE
38:D5:47:32:2D:FE.manufacturer string ASUSTek COMPUTER INC.
38:D5:47:32:2D:FE.bytes number 4529
64:00:6A:97:10:EF table
64:00:6A:97:10:EF.name string 64:00:6A:97:10:EF
64:00:6A:97:10:EF.manufacturer string Dell Inc.
64:00:6A:97:10:EF.bytes number 6034
D0:94:66:3F:AB:1A table
D0:94:66:3F:AB:1A.name string wafivm9.iit.cnr.it
D0:94:66:3F:AB:1A.manufacturer string Dell Inc.
D0:94:66:3F:AB:1A.bytes number 5015
F4:30:B9:D7:6F:53 table
F4:30:B9:D7:6F:53.name string DESKTOP-0L3V5B5
F4:30:B9:D7:6F:53.manufacturer string Hewlett Packard
F4:30:B9:D7:6F:53.bytes number 6942
E8:39:35:20:D0:24 table
E8:39:35:20:D0:24.name string ibiza.iit.cnr.it
E8:39:35:20:D0:24.manufacturer string Hewlett Packard
E8:39:35:20:D0:24.bytes number 935840
D8:9E:F3:3E:CE:7A table
D8:9E:F3:3E:CE:7A.name string DESKTOP-VT7O3KB
D8:9E:F3:3E:CE:7A.manufacturer string Dell Inc.
D8:9E:F3:3E:CE:7A.bytes number 4635
78:E3:B5:8F:8D:02 table
78:E3:B5:8F:8D:02.name string Prosperi-PC
78:E3:B5:8F:8D:02.manufacturer string Hewlett Packard
78:E3:B5:8F:8D:02.bytes number 13431
18:60:24:7B:EB:3B table
18:60:24:7B:EB:3B.name string DESKTOP-U7QMNDS
18:60:24:7B:EB:3B.manufacturer string Hewlett Packard
18:60:24:7B:EB:3B.bytes number 274309
B4:B6:86:13:8D:C7 table
B4:B6:86:13:8D:C7.name string fabio-notebook
B4:B6:86:13:8D:C7.manufacturer string Hewlett Packard
B4:B6:86:13:8D:C7.bytes number 2828
A8:60:B6:2C:5E:87 table
A8:60:B6:2C:5E:87.name string MBP-di-Marina
A8:60:B6:2C:5E:87.manufacturer string Apple, Inc.
A8:60:B6:2C:5E:87.bytes number 911852
00:0C:29:92:D4:04 table
00:0C:29:92:D4:04.name string 00:0C:29:92:D4:04
00:0C:29:92:D4:04.manufacturer string VMware, Inc.
00:0C:29:92:D4:04.bytes number 78099
2C:41:38:98:99:19 table
2C:41:38:98:99:19.name string DESKTOP-QEUC29T
2C:41:38:98:99:19.manufacturer string Hewlett Packard
2C:41:38:98:99:19.bytes number 934164
0C:4D:E9:A2:5B:82 table
0C:4D:E9:A2:5B:82.name string andrea-Macmini
0C:4D:E9:A2:5B:82.manufacturer string Apple, Inc.
0C:4D:E9:A2:5B:82.bytes number 25341
00:E0:4C:14:37:41 table
00:E0:4C:14:37:41.name string MacBook-Pro-5
00:E0:4C:14:37:41.manufacturer string Realtek Semiconductor Corp.
00:E0:4C:14:37:41.bytes number 85359
52:54:00:6B:AA:F4 table
52:54:00:6B:AA:F4.name string 52:54:00:6B:AA:F4
52:54:00:6B:AA:F4.manufacturer string Realtek (UpTech? also reported)
52:54:00:6B:AA:F4.bytes number 14395


  ]]


  dialogflow.send("Work in progress")
end

--WIP
function handler_who_are_protocols()
    --TODO: cicla tra host/dispositivi per vedere CHI ha usato il protocollo

    
  

  dialogflow.send("Work in progress")
end


--########################################################-Intents-Dispatcher-####################################################################
request = dialogflow.receive()

--TODO: intent (triggerabile da vari intent, magari guardo contesto/parametri) per farsi mandare grafici/elenchi via mail (o telegram ecc.)
--TODO: Rework. In alcuni casi è utile che l'utente PRIMA esprima l'intenzione di voler fare qualcosa, POI altro intent per prendere il parametro
--TODO: fai il repeat per tutti (che abbia senso)

--get_aggregated_info può ricevere 4 parametri (Devices, generic, Network, Traffic)
--TODO: fai gli adeguati distinguo per i 4 casi
if      request.intent_name == "get_aggregated_info" then response = handler_get_aggregated_info()
elseif  request.intent_name == "get_aggregated_info - repeat" then response = handler_get_aggregated_info() 
elseif  request.intent_name == "get_aggregated_info - more" then response = handler_get_aggregated_info_more() --WIP & todo handler


--questo intent si differenzia dal "get_aggregated_info --> traffic" perché riguarda solo le applicazioni
--check: ha senso accorparli nello stesso intent? stile get_aggregated_info, creando un'antità per distinguere apps/categories
elseif  request.intent_name == "if_active_flow_top_application" then response = handler_if_active_flow_top_application()
elseif  request.intent_name == "if_active_flow_top_categories"  then response = handler_if_active_flow_top_categories()


  --TODO: metti altri intent per farsi dare elenchi/vai grafici 
elseif  request.intent_name == "who_are - categories"  then response = handler_who_are_categories()--WIP
elseif  request.intent_name == "who_are - protocols"  then response = handler_who_are_protocols()--WIP


  

else response = dialogflow.send("Sorry, but I didn't understand, can you repeat?") 
end

