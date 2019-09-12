--
-- (C) 2019 - ntop.org
--
dirs = ntop.getDirs()
package.path = dirs.installdir .. "/scripts/lua/?.lua;" .. package.path
if((dirs.scriptdir ~= nil) and (dirs.scriptdir ~= "")) then package.path = dirs.scriptdir .. "/lua/modules/?.lua;" .. package.path end
ignore_post_payload_parse = 1

require "lua_utils"
local dialogflow = require "nAssistant/dialogflow_APIv2"
local net_state = require "nAssistant/network_state"
local df_utils = require "nAssistant/dialogflow_utils" --NOTE: poi andranno nelle utils

local response, request

--note: rivedi i limiti una volta implementato il controllo sulla lunghezza delle labels
local limit_num_devices_category_chart = 4
local limit_num_devices_protocol_chart = 4
local limit_num_chart_top_categories  = 6

--TODO: 
--      - SISTEMA I NOMI DEI PERCORSI: NETWORK ha senso diverso nelle info aggregate che in quelle dettagliate!
--      - SPECIFICA SEMPRE QUANDO NON ASPETTI LA RISPOSTA UTENTE! (non ti pubblicano l'app altrimenti)
--      - completa il trasferimento di intent da nAssistant 1 al 2
--      - GUARDA LA SCHEDA PEERS IN HOST_DETAILS (VEDI CODICE E CAPISCI COME FUNGE, C'È ROBA POTENZIALMENTE UTILE)
--      -RICH MESSAGE [https://cloud.dialogflow.com/dialogflow/docs/intents-rich-messages ] inoltre esempi json tra i preferiti
--        idea: nell'URL dell'immagine metto il link al(lo scriptino lua nel) server ntop (o a quanto pare a quickchart.io" ) con alla fine i parametri necessari per fare il grafico
--      -metti altri intent per farsi dare elenchi/vai grafici 
--      -controlla e ragiona sui context lasciati vivi dalle fallback custom!!!! (es: potrei anche deciderli qui, nel back-end)
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
--      -intent per cambiare tipo di grafico quando possibile, rimanendo però sull'intent
--      -aggiungi TANTE frasi per il training

--NOTE/IDEE:
-- !!!  - È possibile salvare dati sul dispositivo dell'utente! [ https://developers.google.com/actions/assistant/save-data ]
--      - come ottengo il nome alias? con getHostAltName(ip,mac) ma ip può essere un mac e mac può essere nil
--      - (dalla docs dei reprompt) Reprompts aren't supported on all Actions on Google surfaces. We recommend you handle no-input errors but keep in mind that they may not appear on all user devices.
--      - Maximum num of suggestion chips is 8, and the maximum text length is 20 characters each.
--      - Mai visto fin'ora: per gestire il fallback a modo: quando accade controllo seè una richiesta nota fatta fuori dall'intent apposito, oppure, contiene frasinote, allora avanzo suggerimenti ad hoc

--+++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
--####################################- nAssistant - UTILS -###############################################
--+++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++

--ABOUT: traffic volume, in/out, TCP efficiency
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

  text = bl_num_txt .. " The communications "..safe_text

  if danger then text = text .. ". \nBut be careful! Dangerous traffic has been detected! " end

  return text
end
  
--#########################################################################################################

--ABOUT: security stuff: alert triggered, bad host, traffic breed
local function get_aggregated_info_network()
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

--ABOUT: summary of the others topic
--#########################################################################################################
local function get_aggregated_info_generic()
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

--return: a table with every host(IP and name) for a specific MAC

--NOTE: qui ho sia host info che mac info, posso combinarle se mi interessa
--"name" può essere una stringa qualunque, è data dall'utente e il chiamante, attualmente, non la controlla
local function find_mac_hosts(name) 

  local hosts_names = interface.findHost(name) --it search "names" among (and inside) all the host names
  if not hosts_names then return 0, nil end

  --tprint(hosts_names)

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
--[[
  QUANDO NON HO RISULTATI DALLA QUERY PARTE QUESTO ERRORE:
    25/Jul/2019 17:48:02 [LuaEngine.cpp:174] ERROR: ntop_set_redis : expected string[@pos 2], got nil

]]

--DOMANDA: ma il nome è legato all'host o al mac? una machina può avere più nomi?
--parte del codice è di find_host.lua
local function find_device_name_and_addresses(query)

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
        res[ip] = hostVisualization(ip, name)     --note: hostVisualization(...) mette "[IPv6]"agli host con ip v6
    end
  end

    --NOTE: in questa cache c'è il problema che ci vengono a finire anche i dispositivi che sono stati "purgiati",
        -- come tratto il caso? se li voglio togliere basta non controllare nella 
        --cache dhcp. MA! attualmente questa funzione viene invocata dall'utente per cercare un dispositivo
        --quindi l'utente presumibilmente vuole info a riguardo, deve poter continuare la ricerca di info. QUINDI:
        --TOLGO IL CONTROLLO IN CACHE

  local ips = {}
  local info_host_by_mac = nil
  local num_items = 0
  for k, v in pairs(res) do
    if num_items >= max_total_items then break end

    if v ~= "" then
      --note: non so se lasciarlo [IPv6], vediamo, se non da noia lascialo
      if isIPv6(v) and (not string.contains(v, "%[IPv6%]")) then
        v = v.." [IPv6]"
      end

      if isMacAddress(v) then         --caso in cui il mac è anche il nome --> v = k
        info_host_by_mac = interface.findHostByMac(v)
        for _,vv in pairs(info_host_by_mac) do
          table.insert(ips,vv)
        end

        results[v] = {name = v, ip = ips}
        num_items = num_items + 1 

      elseif isMacAddress(k) then     --caso in cui la chiave è il mac

        --NOTE: col check alla cache dhcp tolto, pare non avere senso questo caso
        info_host_by_mac = interface.findHostByMac(k)
        for _,vv in pairs(info_host_by_mac) do
          table.insert(ips,vv)
        end
        results[k] = {name = v, ip = ips}
        num_items = num_items + 1 
      else                            --caso in cui ne k ne v sono mac --> k è ip, v è nome

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

--TODO: -METTI UN LIMITE TEMPORALE SE CI SONO MOLTI IP NELLA IP_TABLE
--      -astrai di più! fai una funzione per iterare tra gli host di un mac, che accetti una callback per elaborare le info
--      -studia le varie "duration" in getMacInfo / getHostInfo / categories / app ecc.... (guarda le viste di dettaglio dei mac/host)
--      -ANCHE "total_activity_time" in getHostInfo

--return info about a device and it's hosts
local function merge_hosts_info(ip_table)
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
    local legend_label = "Traffic Breeds (KB)"
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
  --TODO: fai i check, inoltre cerca "parameters.Aggregators" dentro tutto outputContext e non solo in [1] 
  local aggregator = request.parameters.Aggregators or request.outputContext[1].parameters.Aggregators

  --gestisco i 4 differenti casi
  if aggregator == "Generic" then --mega overview
      response_text = get_aggregated_info_generic()

  elseif aggregator == "Traffic" then --traffic / communication
      response_text = get_aggregated_info_traffic()

  elseif aggregator == "Network" then -- security (bad host, dangerous flow)/ alerts
      response_text = get_aggregated_info_network()

  elseif aggregator == "Devices" then --devices/hosts
      response_text = get_aggregated_info_devices()
  
  else
       --fallback qui no ndovrei mai arrivarci
       --non credo ci sia bisogno di implementare una fallback apposita per aggregated_info
      dialogflow.send("Ops! I've a problem, sorry. Ask me something else")--TODO fai un messaggio di errore a modo con link esterno verso una issue di github
      return
  end

  dialogflow.send(response_text, nil, nil, {"top application", "top categories", "general info", "traffic info", "network info", "devices info"})
end

--#########################################################################################################

--TODO
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
  tprint(top_cat)
  local speech_text = df_utils.create_top_categories_speech_text(top_cat) 
  --local display_text = "Here is the chart"

  dialogflow.send(speech_text, display_text, nil, nil, card)
  --dialogflow.send(display_text, nil, nil, nil, card)
end

--#########################################################################################################

--todo: (migliora la performance, faccio una marea di iterazioni sugli host/devices)
function handler_who_is_categories()
  local category = request.parameters.ndpi_category
  local tmp, res, sugg, byte_tot = {}, {}, {}, 0

  ----------------------------------------------------
  local function get_stats_callback(ip, stats)
    
    local h_stats = interface.getHostInfo(stats.ip)

    if h_stats["ndpi_categories"] and h_stats["ndpi_categories"][category] and h_stats["ndpi_categories"][category]["bytes"]then 
        table.insert(tmp, {
          bytes = h_stats["ndpi_categories"][category]["bytes"],
          --manufacturer = stats.manufacturer,
          --name = find_name(mac)
          name = getHostAltName( ip )
      })
      --tprint(mac)
      byte_tot = byte_tot + h_stats["ndpi_categories"][category]["bytes"]
    end

    return true
  end
  -----------------------------------------------------
  net_state.get_stats("localhost", nil, nil, nil, get_stats_callback)
  
  table.sort(tmp, function (a,b) return a.bytes > b.bytes end )

  tprint(tmp)

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
      if string.len(v.name) > 12 then 
        table.insert(data.labels,  string.sub(v.name,1,12) .. "..." )
      else 
        table.insert(data.labels,  v.name)
      end

      table.insert(sugg, v.name)
      table.insert(data.values, math.floor(( v.bytes / byte_tot ) * 100)  ) 
      if i >= limit_num_devices_category_chart then break end    
  end

  local url = df_utils.create_chart_url(data, options)
  local card = dialogflow.create_card(
      "Top ".. category.." Local Hosts Chart",
      url,
      "Top ".. category.." Local Hosts Chart"
  )
  --local speech_text = df_utils.create_top_categories_speech_text(top_cat)
  local display_text = "Here is the chart"

  --dialogflow.send(speech_text, display_text, nil, nil, card)
  dialogflow.send(display_text, nil, nil, sugg, card)
end

--#########################################################################################################

function handler_who_is_protocols()
  local protocol = request.parameters.ndpi_protocol
  local tmp, res, sugg, byte_tot = {}, {}, {}, 0

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
    if string.len(v.name) > 12 then 
      table.insert(data.labels,  string.sub(v.name,1,12) .. "..." )
    else 
      table.insert(data.labels,  v.name)
    end

    table.insert(sugg, v.name)
    table.insert(data.values, math.floor(( v.bytes / byte_tot ) * 100)  ) 
    if i >= limit_num_devices_protocol_chart  then break end    
  end

  local url = df_utils.create_chart_url(data, options)
  local card = dialogflow.create_card(
      "Top ".. protocol.." Local Hosts Chart",
      url,
      "Top ".. protocol.." Local Hosts Chart"
  )
  --local speech_text = df_utils.create_top_categories_speech_text(top_cat)
  local display_text = "Here is the chart"

  --dialogflow.send(speech_text, display_text, nil, nil, card)
  dialogflow.send(display_text, nil, nil, sugg, card)
end

--#########################################################################################################

function handler_ask_for_single_device_info() --in realtà è la fallback dell'intent "ask_for_single_device_info"
  local text = "I didn't find any device with that name, can you repeat please?"
  local device_name = request.queryText
  if (not device_name) or (device_name == "") then dialogflow.send(text); return end
  local macs_table, macs_table_len = find_device_name_and_addresses(device_name) 
  local mac = nil
  local d_info, sugg = {}, {}

  --controllo se un nome trovato è identico alla query (il nome di un device potrebbe essere una parte del nome di un altro, così tratto tale caso)
  local found = false
  local name = nil

  for k,v in pairs(macs_table) do
    if device_name == v.name then 
      found = true
      name = v.name
    end
  end

  if macs_table_len > 1 and not found then 
    text = "I found this, please select one of the suggestions"
  
    for k,v in pairs(macs_table) do
      table.insert(sugg, v.name)
    end

  elseif macs_table_len == 1 or found then 

    for k,v in pairs(macs_table) do
      if macs_table_len == 1 then 
        mac = k
        break
      elseif name and v.name == name then 
        mac = k 
      end
    end 

    d_info = merge_hosts_info(macs_table[mac].ip)

    local alias = ""
    if getHostAltName(mac) ~= d_info.name then 
      alias = " [".. getHostAltName(mac) .." ]"
    end
  

    local discover = require "discover_utils"

    text = "\tName: ".. d_info.name ..alias.."\nType: "..d_info.devtype_name.."\nManufacturer: ".. d_info.manufacturer
    if d_info.model then text = text .."\nModel: "..d_info.model end
    if d_info.operatingSystem then text = text .."\nOS: "..discover.getOsName(d_info.operatingSystem) end
    if d_info.ndpi then text = text .. "\nMost used app: "..d_info.ndpi[1].name end
    if d_info.ndpi_categories then text = text .. "\nMost traffic belong to category: "..d_info.ndpi_categories[1].name end

    sugg = {"more applications", "more categories", "more alerts", "more network", "more security" }

    --TODO: salva un qualche id (mac + i vari host ip? non sarebbe male) del device. serve per il followup intent "more"
    ntop.setCache("nAssistant_device_info_mac", mac, 60*20 ) -- 20 min tempo max di vita

  end

  dialogflow.send(text, nil, nil, sugg)

end

--#########################################################################################################

--in chache troverai l'id (mac + i vari host ip? non sarebbe male, così no ndevo ricalcolarlo, però non è fondamentale)
function handler_ask_for_single_device_info_more()
  local info_type = request.parameters.device_info--note: info type = alerts - applications - security - tech-specs - categories - network
  local mac = ntop.getCache("nAssistant_device_info_mac")
  --TODO: gestisci bene il caso del mac non segnato
  if not (mac and info_type) then dialogflow.send("Please, tell me a specific defice first"); return end

  local macs_table, macs_table_len = find_device_name_and_addresses( getHostAltName(mac))
  local d_info = merge_hosts_info(macs_table[mac].ip)
  local is_chart = false
  local speech_text, display_text = "WIP", "WIP"

  --il seguente è un copia incolla degli intent top app/categories: FAI DELLE FOTTUTE API!
  if not d_info then 
    dialogflow.send("I have not found any active communication! Please try again later")
    return
  end
  ------------------------------------------
  --TODO: usa una sorta di paradigma factory per i chart
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
  local i = 0
  local card_title, chart_description = "Chart", "Chart"

  --note/todo: usare le query dns? capire i siti richiesti e cose del genere? boh
  --            e gli unreachable_flow????

  --TODO: vari check per vedere se tali tabelle non sono nil (andranno nelle utils)
  if     info_type == "applications" then
    is_chart = true
    chart_description = "Top Application for ".. d_info.name 
    card_title = "Top Application for ".. d_info.name

    for _,v in ipairs(d_info.ndpi) do
      table.insert(data.labels, v.name) 
      table.insert(data.values, (v.info["bytes.rcvd"]+v.info["bytes.sent"])/1024 )
      i = i + 1
      if i >= 6 or v.percentage < 1 then break end    --NOTE: 6 and 1 are arbitrary 
    end

  elseif info_type == "categories" then
    is_chart = true
    chart_description = "Top Categories for ".. d_info.name 
    card_title = "Top Categories for ".. d_info.name

    for _,v in ipairs(d_info.ndpi_categories) do
      table.insert(data.labels, v.name)
      table.insert(data.values, v.info.bytes/1024 ) --TODO: se necessario (tanto traffico) metti i MB invece dei KB

      i = i + 1
      if i >= 6 or v.percentage < 1 then break end    --NOTE: 6 and 1 are arbitrary 
    end

  elseif info_type == "alerts" then

    local total_alerts, num_triggered_alerts, tot_triggered_alert = d_info.total_alerts, d_info.num_triggered_alerts,0

    for _,v in pairs(num_triggered_alerts)do tot_triggered_alert = tot_triggered_alert + v end

    display_text = "The device have "..total_alerts.." cumulated alerts and " .. tot_triggered_alert.. " triggered."

    --TODO: il resto delle info per gli alert, ma attualmente le API sono WIP 

  elseif info_type == "security" then

    --d_info.num_blacklisted_host     d_info.num_childSafe_host
    --childsafe (flag che ti dice se è attivo il "safe child dns")

    display_text = "This device have ".. d_info.num_blacklisted_host .. " blacklisted host, "..
        d_info.num_childSafe_host .. " of them have child-safe turn on.\nHere you have a chart about the security of traffic:"

    is_chart = true
    chart_description = "Traffic Breed for ".. d_info.name 
    card_title = "Traffic Breed for ".. d_info.name

    local breeds_table = {}

    for _,v in ipairs(d_info.ndpi) do
      if breeds_table[v.info.breed] then 
        breeds_table[v.info.breed] = breeds_table[v.info.breed] + v.info["bytes.rcvd"] + v.info["bytes.sent"]
      else
        breeds_table[v.info.breed] = v.info["bytes.rcvd"] + v.info["bytes.sent"]
      end
    end

    for ii,v in pairs(breeds_table) do
      table.insert(data.labels, ii) 
      table.insert(data.values, (v/1024) )
      i = i + 1
      if i >= 6 then break end    --NOTE: 6 and 1 are arbitrary 
    end

    speech_text = display_text --TODO: change this, is temporary

  elseif info_type == "network" then

    --TODO: goodput, tcpPktStats per l'efficienza, 

    --TODO: sempre i vari check sulle tabelle prima di iterarci

    --TODO: pensa un modo elencare LE interfacce attive
    -- local if_name = interface.getIfNames()[d_info.ifid]

    display_text = "Interface Name = "..ifname.."\nAddresses:\nMAC = "..mac

    local i = 1--TODO: trova modo per recuperare gli ip
    -- for _,v in pairs(macs_table) do
    --   display_text = display_text .. "\n\tIP Host("..i..") = "..v[i].ip
    -- end

    local tot_sent, tot_rcvd = 0,0
    for i,v in pairs(d_info.ndpi_categories) do --scelgo le categories perché quasi certamente contiene meno elementi
      tot_sent = tot_sent + v.info["bytes.sent"]
      tot_rcvd = tot_rcvd + v.info["bytes.rcvd"]
    end

    display_text = display_text .. "\nApplications Traffic Volume(KB):\n\tsent/rcvd = "..
      string.format("%.2f",tot_sent/1024).." / "..string.format("%.2f",tot_rcvd/1024)

  else
    --problemi! in teoria qui non dovrei mai capitarci
  end 

  if is_chart then 
    local url = df_utils.create_chart_url(data, options)
    local card = dialogflow.create_card(card_title, url, chart_description)
    
    if display_text == "WIP" then  display_text = "Here is the chart" end

    dialogflow.send(speech_text, display_text, nil,  {"more applications", "more categories", "more alerts", "more network", "more security" }, card)
  else
    dialogflow.send(display_text, nil, nil, {"more applications", "more categories", "more alerts", "more network", "more security" } )
  end
end

--#########################################################################################################

function handler_get_single_device_info_from_who_is()
  local text = ternary( -- great randomization!
        os.time()%2==0 ,
        "Sorry, I didn't understand correctly. Can you repeat, please? ",
        "Sorry I didn't understand what you mean, can you please repeat?"
      )
  local device_name = request.queryText
  if (not device_name) or (device_name == "") then dialogflow.send(text); return end

  local macs_table_len, macs_table, mac = find_mac_hosts(device_name)
  local d_info = {}

  if macs_table_len > 1 then 
    --TODO: metti suggerimenti e diversifica la risposta audio
    text = "I found this, please select one of the suggestions"

  elseif macs_table_len == 1 then 
    d_info = merge_hosts_info(macs_table[mac].ip)

    local discover = require "discover_utils"
  
    text = "\tName: ".. d_info.name .. "\nType: "..d_info.devtype_name.."\nManufacturer: ".. d_info.manufacturer
    if d_info.model then text = text .."\nModel: "..d_info.model end
    if d_info.operatingSystem then text = text .."\nOS: "..getOsName(d_info.operatingSystem) end
    if d_info.ndpi then text = text .. "\nMost used app: "..d_info.ndpi[1].name end
    if d_info.ndpi_categories then text = text .. "\nMost traffic belong to category: "..d_info.ndpi_categories[1].name end

  end
  --TODO: salva un qualche id (mac + i vari host ip? non sarebbe male) del device. serve per il followup intent "more"
  ntop.setCache("nAssistant_device_info_mac", mac, 60*20 ) -- 20 min tempo max di vita

  dialogflow.send(text)
end

--+++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
--########################################################-Intents-Dispatcher-###################################################################
--+++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
request = dialogflow.receive()

--get_aggregated_info può ricevere 4 parametri (Devices, generic, Network, Traffic)
if      request.intent_name == "get_aggregated_info" then response = handler_get_aggregated_info()
elseif  request.intent_name == "get_aggregated_info - repeat" then response = handler_get_aggregated_info() 
elseif  request.intent_name == "get_aggregated_info - more" then response = handler_get_aggregated_info_more() --WIP & todo handler

--questo intent si differenzia dal "get_aggregated_info --> traffic" perché riguarda solo le applicazioni
--check: ha senso accorparli nello stesso intent? stile get_aggregated_info, creando un'entità per distinguere apps/categories per ora direi di NO,
--       i due intent sui aspettano entity diverse, se le accorpo come faccio a distinguere? --> composite entity! non va perché il nome del proto/categoria deve essere obbligatorio MA è in base a cosa ha detto l'utente! se vuole i proto o le categorie!
elseif  request.intent_name == "if_active_flow_top_application" then response = handler_if_active_flow_top_application()
elseif  request.intent_name == "if_active_flow_top_categories"  then response = handler_if_active_flow_top_categories()

elseif  request.intent_name == "who_is - categories" then response = handler_who_is_categories()--WIP
elseif  request.intent_name == "who_is - protocols"  then response = handler_who_is_protocols()--WIP

--CHECK: nuovo contesto per gli "who_is" così da poter triggerare l'individuazione del nome dell'host/device da lì (es tappando sul suggerimento)
elseif  request.intent_name == "ask_for_single_device_info - fallback" then response = handler_ask_for_single_device_info()

  --info dettagliate relative a: categorie, app, sicurezza (aggiungiere altre, tipo i talkers se la matrice è attiva??)
elseif  request.intent_name == "ask_for_single_device_info - fallback - more" then response = handler_ask_for_single_device_info_more()

--intent who_are_you implementato direttamente su dialogflow!  

-----------------------------------------------------------------------------
--TODO: sarebbe meglio fare altri intent per il "who_is..." che parte dalle info del singolo device e non da "top_..."
elseif  request.intent_name == "who_is - categories - fallback" then response = handler_ask_for_single_device_info() --handler_get_single_device_info_from_who_is()
elseif  request.intent_name == "who_is - protocols - fallback" then response = handler_ask_for_single_device_info() --handler_get_single_device_info_from_who_is()
-------------------------------------------------------------------------------


--IDEA: per il repeat facci oun intent solo, generico, e quando capita guardo in cache e replico l'ultimo intent con relativi param ecc:
--potrei salvarmi l'intera precedente richiesta! e simulare che arrivi (occhio solo a più rietizioni conecutive)


else response = dialogflow.send("Sorry, but I didn't understand, can you repeat please?") 
end

