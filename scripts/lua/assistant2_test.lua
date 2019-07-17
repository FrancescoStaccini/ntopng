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
local df_utils = require "dialogflow_utils" --TODO: poi spostale le utils (o valuta se ha senso questo grado di modularità)

local response, request

--note: rivedi i limiti una volta implementato il controllo sulla lunghezza delle labels
local limit_num_devices_category_chart = 4
local limit_num_devices_protocol_chart = 4
local limit_num_chart_top_categories  = 6

--TODO: 
--      -RICH MESSAGE [https://cloud.dialogflow.com/dialogflow/docs/intents-rich-messages ] inoltre esempi json tra i preferiti
--        idea: nell'URL dell'immagine metto il link al(lo scriptino lua nel) server ntop (o a quanto pare a quickchart.io" ) con alla fine i parametri necessari per fare il grafico
--      -metti altri intent per farsi dare elenchi/vai grafici 
--      -CANCELLA I VECCHI FILE: google_assistant_utils.lua ecc.
--      -sistema (chiedi aiuto per) l'inglese
--      -AGGIUNGI I SUGGERIMENTI (ovunque ha senso, soprattutto nei grafici)
--          function ga_module.send(speech_text, display_text, expect_response, suggestions_strings, card )
--      -nella creazione delle card per i grafici, controlla/taglia la lunghezza dellle labels per farle entrare nel grafico
--      -telegram bot: guarda se, a posteriori dell'apertura della chat da parte dell'utente, è possibile prendersi il chatID (e il token come lo piglio? hardcoded? ma è pubblico il codice!)
--      -sinonimi della entity ndpi_protocols (devono essere "assistant friendly" cioè pensa a come l'assistente comprende le parole). idea: per le lettere maiuscole, "abbassale" programmaticamente
--      -idea: quickchart.io permette di fare anche qr_code: magari si possono usare per linkare roba interessante? pensaci su
--      -intent (triggerabile da vari intent, magari guardo contesto/parametri) per farsi mandare grafici/elenchi via mail (o telegram ecc.)
--      -Intents Rework. In alcuni casi è utile che l'utente PRIMA esprima l'intenzione di voler fare qualcosa, POI altro intent per prendere il parametro
--      -fai il repeat per tutti gli intent (che abbia senso)
--      -Aggiungere dimensione temporale nelle info (tipo traffico/app/categorie ecc.) così d adare un idea del tempo di monitoraggio
--      -aggiungere la getHostAltName(ip,mac) dove serve ma occhio! mettila solo quando devi esporre i dati!
--      -la possibilità di settare Alias per i dispositivi, direttamente dall'assistente

--NOTE:
--      - come ottengo il nome alias? con getHostAltName(ip,mac) ma ip può essere un mac e mac può essere nil
--      - (dalla docs dei reprompt) Reprompts aren't supported on all Actions on Google surfaces. We recommend you handle no-input errors but keep in mind that they may not appear on all user devices.


--+++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
--####################################- nAssistant - UTILS -###############################################
--+++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++

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

local function get_aggregated_info_network()
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
local function get_aggregated_info_generic()
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

--#########################################################################################################
--return: a table with every host(IP and name) for a specific MAC
--NOTE: qui ho sia host info che mac info, posso combinarle se mi interessa


--todo: REWORK! FAI CHE RITORNA SOLO GLI INDIRIZZI TROVATI, POI UN'ALTRA FUNZIONE CHE MERGIA LE INFO DI TUTTI GLI HOST DI TALE MAC

--"name" può essere una stringa qualunque, è data dall'utente e il chiamante, attualmente, non la controlla
local function find_mac_hosts(name) 

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
--TODO: studia le varie "duration" in getMacInfo / getHostInfo / categories / app ecc.... (guarda le viste di dettaglio dei mac/host)
--return info about a device and its hosts
local function merge_hosts_info(ip_table)
  local res = nil
  local ndpi_categories_tot_bytes, ndpi_tot_bytes = 0, 0

  for _,v in ipairs(ip_table) do   --fondo insieme le tavole
    --[[
    

      TODO: controlla se il num di bytes torna con le ndpi app e coi i bytes inviai/ricevuti su getMAc/HostInfo(..) )   )

      TODO: le varie info per stabilire se la connessione è buona. aspetto che tale lavoro (anche se aggregato) venga fatto su network_state perché
        sono state introdotte nuove info da controllare e c'è da rifare roba
    ]]

    tmp = interface.getHostInfo(v.ip)

    if res == nil then --tabella vuota, popolo con le info che sono uguali per ogni host del device, lo faccio solo la prima volta
      --attualmente tengo più info di quante ne uso:
      --TODO:(salta http - sites - dns che li vedrei solo della macchina dove gira ntopng, però i contatori dei metodi hhtp funzionano ugualmente)
      --la tabella di ndpi_categories e ndpi, tutta. dagli host
      
      res = tmp 
      local mac_info = interface.getMacInfo(tmp.mac)

      if tmp.devtype and tmp.devtype ~= 0 then 
        local discover = require "discover_utils" 
        res["devtype_name"] = discover.devtype2string(tmp.devtype) 
      else 
        res["devtype_name"]  = "Unknown"
      end

      res["manufacturer"] = ternary( mac_info and mac_info.manufacturer, mac_info.manufacturer, "Unknown"  )
      res["model"] = ternary( mac_info and mac_info.model, mac_info.model, "Unknown"  )
      res["operatingSystem"] = ternary( mac_info and mac_info.operatingSystem ~= 0, getOperatingSystemName(mac_info.operatingSystem), "Unknown"  )
      --TODO: info sulla pool
      --TODO: first_seen/last_seen guardalo da mac_details (ed il First Observed On??)
      --[[
        qui unisco con getMacInfo(), cioè le info sottostanti

          da get info mac:
          "seen.first":1563193569,
          "model":"MacBookPro12,1"
          "manufacturer":"Apple, Inc."
          "operatingSystem":0
          "duration":9973, -- guarda a che si riferisce
          "pool":0,
          "duration":9973, ma duration de che?

      ]]
    else --qui faccio i merge
      ------ndpi_categories------
      for name, info in pairs(tmp.ndpi_categories) do
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
      for name, info in pairs(tmp.ndpi) do
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
      ---------------
      if tmp.is_blacklisted and tmp.is_blacklisted == "true" then res["is_blacklisted"] =  "true" end -- lo metto solo se è true
      res["num_alerts"] = res["num_alerts"] + tmp["num_alerts"]
      res["total_alerts"] = res["total_alerts"] + tmp["total_alerts"]

      --note faccio ciò per togliere il tag [...] a seguito del nome ( es. nome & nome [IPv6] )
      if tmp.name and ( string.len(res.name) > string.len(tmp.name) ) then res.name = tmp.name end

    end
  end--end-for

  --ordino ndpi app e categories
  tmp = {}
  if res.ndpi then 
    for i,v in pairs(res.ndpi) do
      table.insert(tmp, {name = i, info = v, percentage = math.floor( ( (v["bytes.rcvd"] + v["bytes.sent"]) / ndpi_tot_bytes) * 100 ) } )
    end
    table.sort(tmp, function (a,b) return ( a.info["bytes.rcvd"] + a.info["bytes.sent"] ) > (b.info["bytes.sent"] + b.info["bytes.rcvd"]) end)
    res.ndpi = tmp
  end

  tmp = {}
  if res.ndpi_categories then 
    for i,v in pairs(res.ndpi_categories) do
      table.insert(tmp, {name = i, info = v, percentage = math.floor( (v.bytes / ndpi_categories_tot_bytes) * 100 ) } )
    end
    table.sort(tmp, function (a,b) return a.info.bytes > b.info.bytes end)
    res.ndpi_categories = tmp
  end

  return res
end


--+++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
--#######################################- INTENTS HANDLERS -##############################################
--+++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++

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
        table.insert(data.values, v.bytes/1024 )
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

--#########################################################################################################

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
       dialogflow.send("Ops! I've a problem, sorry. Ask me something else")--TODO fai un messaggio di errore a modo con link esterno verso una issue di github
  end

  dialogflow.send(response_text)
end

--#########################################################################################################

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

--#########################################################################################################

--WIP
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
      if i >= limit_num_chart_top_categories or v.perc < 1 then break end   
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

--#########################################################################################################

--WIP
--todo: SISTEMA NOMI, METTILI IN UN GRAFICO, (E SE MIGLIORI LE PREFORMANCE ALLORA TOP, faccio una marea di iterazioni sugli host/devices)
function handler_who_is_categories()
  local category = request.parameters.ndpi_category
  local tmp, res, byte_tot = {}, {}, 0

  ----------------------------------------------------
  local function get_stats_callback(mac, stats)
    if stats["ndpi_categories"] and stats["ndpi_categories"][category] and stats["ndpi_categories"][category]["bytes"]then 
        table.insert(tmp, {
          bytes = stats["ndpi_categories"][category]["bytes"],
          manufacturer = stats.manufacturer,
          --name = find_name(mac)
          name = getHostAltName( mac )
      })
      byte_tot = byte_tot + stats["ndpi_categories"][category]["bytes"]
    end
  end
  -----------------------------------------------------
  net_state.get_stats("devices", nil, nil, nil, get_stats_callback)
  
  table.sort(tmp, function (a,b) return a.bytes > b.bytes end )

  local labels, values, datasets = {},{},{}
  local legend_label = "Traffic Volume (percentage)"
  local data = {labels = {}, values = {}, legend_label = legend_label}
  local options = { 
      w = "600",
      h = "280",
      chart_type = "bar",
      bkg_color = "white"
  }
  for i,v in ipairs(tmp) do
      table.insert(data.labels,  v.name)
      table.insert(data.values, math.floor(( v.bytes / byte_tot ) * 100)  ) 
      if i >= limit_num_devices_category_chart then break end    
  end

  local url = df_utils.create_chart_url(data, options)
  local card = dialogflow.create_card(
      "Top ".. category.." Device Chart",
      url,
      "Top ".. category.." Device Chart"
  )
  --local speech_text = df_utils.create_top_categories_speech_text(top_cat)
  local display_text = "Here is the chart"

  --TODO: aggiungi i suggerimenti coi nomi dei dispositivi e la parte vocale
  --dialogflow.send(speech_text, display_text, nil, nil, card)
  dialogflow.send(display_text, nil, nil, nil, card)
end

--#########################################################################################################

--WIP
--todo: sistema il grafico: i nomi sono lunghi e le label "sballano il grafico" ed a volte si sballa per non so quale motivo :(
function handler_who_is_protocols()
  local protocol = request.parameters.ndpi_protocol
  local tmp, res, byte_tot = {}, {}, 0

  ----------------------------------------------------
  local function get_stats_callback(ip)

    local host_stats = interface.getHostInfo(ip)

    if not host_stats then return false end

    if host_stats["ndpi"] and host_stats["ndpi"][protocol] then 
        table.insert(tmp, {
          bytes = host_stats["ndpi"][protocol]["bytes.sent"] + host_stats["ndpi"][protocol]["bytes.rcvd"],
          --name = ternary(host_stats.name ~= "", host_stats.name, ip)
          name = getHostAltName(ip)
      })
      byte_tot = byte_tot +  host_stats["ndpi"][protocol]["bytes.sent"] + host_stats["ndpi"][protocol]["bytes.rcvd"] 
    end

    return true
  end
  -----------------------------------------------------
  net_state.get_stats("localhost", nil, nil, nil, get_stats_callback)
  
  table.sort(tmp, function (a,b) return a.bytes > b.bytes end )

  local labels, values, datasets = {},{},{}
  local legend_label = "Traffic Volume (percentage)"
  local data = {labels = {}, values = {}, legend_label = legend_label}
  local options = { 
      w = "600",
      h = "280",
      chart_type = "bar",
      bkg_color = "white"
  }
  for i,v in ipairs(tmp) do
      table.insert(data.labels, v.name)
      table.insert(data.values, math.floor(( v.bytes / byte_tot ) * 100)  ) 
      if i >= limit_num_devices_protocol_chart  then break end    
  end

  local url = df_utils.create_chart_url(data, options)
  local card = dialogflow.create_card(
      "Top ".. protocol.." Device Chart",
      url,
      "Top ".. protocol.." Device Chart"
  )
  --local speech_text = df_utils.create_top_categories_speech_text(top_cat)
  local display_text = "Here is the chart"

  --TODO: aggiungi i suggerimenti coi nomi dei dispositivi e la parte vocale
  --dialogflow.send(speech_text, display_text, nil, nil, card)
  dialogflow.send(display_text, nil, nil, nil, card)
end

--#########################################################################################################

--TODO: alla risposta, comunica anche il nome che ho inteso del dispositivo
function handler_ask_for_single_device_info() --in realtà è la fallback dell'intent "ask_for_single_device_info"
  local text = "I didn't find any device with that name"
  local device_name = request.queryText

  local macs_table_len, macs_table, mac = find_mac_hosts(device_name)
  local d_info = {}

  if macs_table_len > 1 then 
    --TODO: metti suggerimenti (ed elenco testuale) e fai in modo che il suggerimento selezionato venga accettato/inteso
    text = "I found this, please select one of the suggestions"

  elseif macs_table_len == 1 then
    
    d_info = merge_hosts_info(macs_table[mac])
  
    text = "\tName: ".. d_info.name .. "\nType: "..d_info.devtype_name.."\nManufacturer: ".. d_info.manufacturer
    
    if d_info.model then text = text .."\nModel: "..d_info.model end

    if d_info.ndpi then text = text .. "\nMost used app: "..d_info.ndpi[1].name end
    if d_info.ndpi_categories then text = text .. "\nMost traffic is about: "..d_info.ndpi_categories[1].name end

  end

  --TODO: salva un qualche id (mac + i vari host ip? non sarebbe male) del device. serve per il followup intent "more"
  ntop.setCache("nAssistant_device_info_mac", mac, 60*20 ) -- 20 min tempo max di vita
  tprint(mac)

  --tprint(d_info)
  dialogflow.send(text)

end

--#########################################################################################################

function handler_ask_for_single_device_info_more()
  --nel param device_info trovi cosa devi controllare, in chache troverai l'id (mac + i vari host ip? non sarebbe male)
  local info_type = request.parameters.device_info
  --note: info type = alarm - application - security - specification - traffic category


  local mac = ntop.getCache("nAssistant_device_info_mac")

  tprint(mac)

  local macs_table_len, macs_table = find_mac_hosts(mac)
  local d_info = merge_hosts_info(macs_table[mac])


--il seguente è un copia incolla dei top app/categories: FAI DELLE FOTTUTE API!
  if not d_info then 
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
  local t = {}
  --TODO: vari check per vedere se tali tabelle non sono nil
  if info_type == "application" then t = d_info.ndpi end 
  --MA OCCHIO CHE PER COME VENGONO CARICATI I VALUES QUA SOTTO, NELLE ndpi_categories NON CI SONO I bytes ma i bytes.rcvd e send!!!!

  tprint(d_info.ndpi)

  local i = 0
  for _,v in ipairs(t) do
      table.insert(data.labels, v.name)
      
      table.insert(data.values, (v.info["bytes.rcvd"]+v.info["bytes.sent"])/1024 )

      --SOPRA C'È SOLUZIONE TEMPORANEA, DA SISTEMARE
      --table.insert(data.values, v.bytes/1024 ) --TODO: se necessario (tanto traffico) metti i MB invece dei KB
      i = i + 1
      if i >= 6 or v.percentage < 1 then break end    --NOTE: 6 and 1 are arbitrary
  end

  local url = df_utils.create_chart_url(data, options)
  local card = dialogflow.create_card(
      "Top Application for ".. d_info.name ,
      url,
      "Top Application Chart"
  )
  local speech_text = "WIP"
  local display_text = "Here is the chart"

  dialogflow.send(speech_text, display_text, nil, nil, card)





  dialogflow.send("WIP, man!")
end
--+++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
--########################################################-Intents-Dispatcher-###################################################################
--+++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
request = dialogflow.receive()

--get_aggregated_info può ricevere 4 parametri (Devices, generic, Network, Traffic)
--TODO: fai gli adeguati distinguo per i 4 casi
if      request.intent_name == "get_aggregated_info" then response = handler_get_aggregated_info()
elseif  request.intent_name == "get_aggregated_info - repeat" then response = handler_get_aggregated_info() 
elseif  request.intent_name == "get_aggregated_info - more" then response = handler_get_aggregated_info_more() --WIP & todo handler


--questo intent si differenzia dal "get_aggregated_info --> traffic" perché riguarda solo le applicazioni
--check: ha senso accorparli nello stesso intent? stile get_aggregated_info, creando un'entità per distinguere apps/categories per ora direi di NO,
--       i due intent sui aspettano entity diverse, se le accorpo come faccio a distinguere? --> composite entity! non va perché il nome del proto/categoria deve essere obbligatorio MA è in base a cosa ha detto l'utente! se vuole i proto o le categorie!
elseif  request.intent_name == "if_active_flow_top_application" then response = handler_if_active_flow_top_application()
elseif  request.intent_name == "if_active_flow_top_categories"  then response = handler_if_active_flow_top_categories()


  --TODO: aggiungi frasi per il training
elseif  request.intent_name == "who_is - categories"  then response = handler_who_is_categories()--WIP
elseif  request.intent_name == "who_is - protocols"  then response = handler_who_is_protocols()--WIP


--TODO: di questi qua sotto cambia i nomi in qualcosa di più leggibile, MA ATTENTO, prima guardati bene "action and parameters" perché devi comunque portarti dietro le info tra i contesti
--CHECK: nuovo contesto per gli "who_is" così da poter triggerare l'individuazione del nome dell'host/device da lì (es tappando sul suggerimento)
elseif  request.intent_name == "ask_for_single_device_info - fallback" then response = handler_ask_for_single_device_info()

  --info dettagliate relative a: categorie, app, sicurezza, tech specs, (aggiungiere altre, tipo i talkers se la matrice è attiva??)
elseif  request.intent_name == "ask_for_single_device_info - fallback - more" then response = handler_ask_for_single_device_info_more()


  


else response = dialogflow.send("Sorry, but I didn't understand, can you repeat please?") 
end

