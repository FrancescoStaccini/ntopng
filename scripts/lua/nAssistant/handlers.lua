--
-- (C) 2019 - ntop.org
--
dirs = ntop.getDirs()
package.path = dirs.installdir .. "/scripts/lua/?.lua;" .. package.path
if((dirs.scriptdir ~= nil) and (dirs.scriptdir ~= "")) then package.path = dirs.scriptdir .. "/lua/modules/?.lua;" .. package.path end

require "lua_utils"
local h_utils = require "nAssistant/handlers_utils" 
local dialogflow = require "nAssistant/dialogflow_APIv2"
local net_state = require "nAssistant/network_state"
local df_utils = require "nAssistant/dialogflow_utils"


--note: rivedi i limiti una volta implementato il controllo sulla lunghezza delle labels e charts a modo
local label_max_len = 18
local limit_num_devices_category_chart = 4
local limit_num_devices_protocol_chart = 4
local limit_num_chart_top_categories  = 6
local limit_num_suggestions = 12
local limit_num_top_host = 5
local limit_num_ndpi_proto_chart = 6
local limit_num_ndpi_categories_chart = 6

local handlers_module = {}

--#########################################################################################################
local ntop_response = {}

--TODO: rivedi gli aggregatori
function handlers_module.get_aggregated_info(user_request)
  local response_text = ""

  local aggregator = user_request.queryResult.parameters.Aggregators --[ https://dialogflow.cloud.google.com/#/agent/68176235-60ff-4d2b-a0ef-ef9ae97bf48e/entities ]

  if aggregator == "Generic" then 
      response_text = h_utils.get_aggregated_info_generic()

  elseif aggregator == "Traffic" then 
      response_text = h_utils.get_aggregated_info_traffic()

  elseif aggregator == "Network" then 
      response_text = h_utils.get_aggregated_info_network()

  elseif aggregator == "Devices" then 
      response_text = h_utils.get_aggregated_info_devices()
  
  else
       --arrivo qui solo se lo "switch" sopra non è sincronizzato con la Dialogflow Entity
       --TODO: gestisci la cosa con una qualche sorta di segnalazione interna
      response_text = "Ops! I've a problem, sorry. Ask me something else"
  end

  ntop_response.speech_text = response_text
  ntop_response.display_text = response_text
  ntop_response.suggestions = {"top application", "top categories", "general info", "traffic info", "network info", "devices info"}

  return ntop_response
end

--#########################################################################################################

function handlers_module.if_active_flow_top_application(user_request)
    local top_app = net_state.check_top_application_protocol() 
    --note: top app is in decrescent order and contain, for each proto, [name-percent-bytes]
    if not top_app then 
        ntop_response.speech_text = "I have not found any active communication! Please try again later"
        return ntop_response
    end

    --TODO: cambia tipo di grafico! vistoche dice le percentuali, metti grafici pie/doughnut
    --local legend_label = "Traffic Breeds (KB)"
    local data = {labels = {}, values = {}--[[, legend_label = legend_label]]}
    local options = { 
      w = "500",
      h = "300",
      chart_type = "outlabeledPie", 
      bkg_color = "white",
      outlabels_text = "%l %v KB",
      legend_labels_font_size = 12,
      outlabels_stretch = 17,
      show_legend = false
    }
    local i = 0

    --note: in this way the chart 
    for _,v in ipairs(top_app) do
        table.insert(data.labels, v.name)
        table.insert(data.values,  tonumber(string.format("%.2f", v.bytes/1024)) )
        i = i + 1
        if i >= 6 or v.percentage < 1 then break end    --NOTE: 5 and 1 are arbitrary
    end

    local url = df_utils.create_chart_url(data, options)
    local image =  {img_url = url,img_description = "Top Application Chart" }
    local opt = { title = "Top Application Chart" }
    local card = dialogflow.create_card(nil, image, opt  )
    local speech_text = df_utils.create_top_traffic_speech_text(top_app)

    ntop_response.speech_text = speech_text
    ntop_response.display_text = speech_text
    ntop_response.card = card

    return ntop_response
end

--#########################################################################################################

--TODO?
--function handlers_module.get_aggregated_info_more(user_request)
  -- local response_text = ""

  -- local aggregator = user_request.queryResult.parameters.Aggregators

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

  -- ntop_response.speech_text = response_text
  -- ntop_response.display_text = response_text
  -- ntop_response.suggestions = sugg
  -- ntop_response.card = card

  -- return ntop_response
--end

--#########################################################################################################

function handlers_module.if_active_flow_top_categories(user_request)
  local top_cat = net_state.check_traffic_categories()
  --note: top app is in decrescent order and contain, for each caregory, [name-perc-bytes]
  if not top_cat then 
      ntop_response.speech_text = "I have not found any active communication! Please try again later"
      return ntop_response
  end
  --local legend_label = "Traffic Breeds (KB)"
  local data = {labels = {}, values = {}--[[, legend_label = legend_label]]}
  local options = { 
    w = "500",
    h = "300",
    chart_type = "outlabeledPie", 
    bkg_color = "white",
    outlabels_text = "%l %v KB",
    legend_labels_font_size = 12,
    outlabels_stretch = 17,
    show_legend = false
  }
  local i = 0
  for _,v in ipairs(top_cat) do
      table.insert(data.labels, v.name)
      table.insert(data.values, tonumber(string.format("%.2f", v.bytes/1024)) ) --TODO: all'occorrenza metti MB invece dei KB
      i = i + 1
      if i >= limit_num_chart_top_categories or v.perc < 1 then break end   
  end
 
  local url = df_utils.create_chart_url(data, options)
  local image =  {img_url = url, img_description = "Top Categories Chart" }
  local opt = { title = "Top Categories Chart" }
  local card = dialogflow.create_card(nil, image, opt  )

  local speech_text = df_utils.create_top_categories_speech_text(top_cat) 

  ntop_response.speech_text = speech_text
  ntop_response.display_text = speech_text
  --ntop_response.suggestions = sugg    --TODO!
  ntop_response.card = card

  return ntop_response
end

--#########################################################################################################

--TODO: speech and display text
-- (migliora la performance, faccio molte iterazioni sugli host/devices)
function handlers_module.who_is_categories(user_request)
  local category = user_request.parameters.ndpi_category
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
  local image =  {img_url = url, img_description = "Top ".. category.." Local Hosts Chart" }
  local opt = { title = "Top ".. category.." Local Hosts Chart" }
  local card = dialogflow.create_card(nil, image, opt  )
  
  local display_text = "Here is the chart (WIP)" 
  local speech_text =  "Here is the chart"

  ntop_response.speech_text = speech_text
  ntop_response.display_text = display_text
  ntop_response.suggestions = sugg    
  ntop_response.card = card

  return ntop_response
end

--#########################################################################################################

--TODO: speech/display text
function handlers_module.who_is_protocols(user_request)
  local protocol = user_request.queryResult.parameters.ndpi_protocol
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

  local image =  {img_url = url, img_description = "Top ".. protocol.." Local Hosts Chart" }
  local opt = { title = "Top ".. protocol.." Local Hosts Chart" }
  local card = dialogflow.create_card(nil, image, opt  )
  
  local speech_text = "Here is the chart"
  local display_text = "Here is the chart"

  ntop_response.speech_text = speech_text
  ntop_response.display_text = display_text
  ntop_response.suggestions = sugg    
  ntop_response.card = card

  return ntop_response
end

--#########################################################################################################

function handlers_module.device_info(user_request) -- fallback dell'intent "ask_for_single_device_info"
  local text = "I don't get it, can you repeat please?"
  local device_name = user_request.queryResult.queryText
  if (not device_name) or (device_name == "") then
    ntop_response.speech_text =  text 
    return ntop_response
  end

  local macs_table, macs_table_len = h_utils.find_device_name_and_addresses(device_name) 
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

    d_info = h_utils.merge_hosts_info(macs_table[mac].ip)

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

    ntop.setCache("nAssistant_device_info_mac", mac, 60*20 )
  end

  ntop_response.speech_text = text
  ntop_response.display_text = text
  ntop_response.suggestions = sugg    

  return ntop_response
end

--#########################################################################################################

--TODO: speech_text e MOLTO altro. da rivedere
--in chache troverai l'id (mac + i vari host ip? non sarebbe male, così no ndevo ricalcolarlo, però non è fondamentale)
function handlers_module.device_info_more(user_request)
  local info_type = user_request.queryResult.parameters.device_info--note: info type = alerts - applications - security - tech-specs - categories - network
  local mac = ntop.getCache("nAssistant_device_info_mac") --NOTE: gli handler predecessori di questo divranno settare il mac del dispositivo corrente in cache!

  --TODO: gestisci bene il caso del mac non segnato
  if not (mac and info_type) then 
    ntop_response.speech_text = "Please, tell me a specific defice first" --TODO: va bene? è una fallback, se l'utente chiede cose strane in quel momento del dialogo gli verrà risposto così anche se non è pertinente! 
    return ntop_response
  end

  local macs_table, macs_table_len = h_utils.find_device_name_and_addresses( mac ) -- non funziona perfettamente, a volte non trova il nome dell'host
  -- a volte sembra meglio usre getHostAltName(mac)nella find, altre volter no. indaga e sistema

  local d_info = h_utils.merge_hosts_info(macs_table[mac].ip)
  local is_chart = false
  local speech_text, display_text = "WIP", "WIP"

  --il seguente è un copia incolla degli intent top app/categories: FAI DELLE API!
  if not d_info then 
    ntop_response.speech_text =  "I have not found any active communication! Please try again later"
    return ntop_response
  end
  ------------------------------------------
  --TODO: usa una sorta di manager (factory) per i chart
  local labels, values, datasets = {},{},{}
  local legend_label = "Traffic (KB)"
  local data = {labels = {}, values = {}, legend_label = legend_label}
  local options = { 
      w = "600",
      h = "280",
      chart_type = "doughnut",
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
      if i >= 6 or v.percentage < 1 then break end    --NOTE: togli le costanti e metti i limiti
    end

  elseif info_type == "alerts" then --TODO: unisci con security

    local total_alerts, num_triggered_alerts, tot_triggered_alert = d_info.total_alerts, d_info.num_triggered_alerts,0

    for _,v in pairs(num_triggered_alerts)do tot_triggered_alert = tot_triggered_alert + v end

    display_text = "The device have "..total_alerts.." cumulated alerts and " .. tot_triggered_alert.. " triggered."

  elseif info_type == "security" then
    --d_info.num_blacklisted_host     d_info.num_childSafe_host
    --childsafe (flag che ti dice se è attivo il "safe child dns")

    display_text = "This device have ".. d_info.num_blacklisted_host .. " blacklisted host.\nHere you have a chart about the security of traffic:"
        --d_info.num_childSafe_host .. " of them have child-safe turn on.\nHere you have a chart about the security of traffic:"
      
    is_chart = true
    --traffic breed graph:
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

  local sugg = {"more applications", "more categories", "more alerts", "more network", "more security" }

  if is_chart then 
    local url = df_utils.create_chart_url(data, options)
    local image =  {img_url = url, img_description = chart_description }
    local opt = { title = card_title}
    local card = dialogflow.create_card(nil, image, opt  )
    
    if display_text == "WIP" then  display_text = "Here is the chart" end

    ntop_response.speech_text = speech_text
    ntop_response.display_text = display_text
    ntop_response.suggestions = sugg    
    ntop_response.card = card
  else
    ntop_response.speech_text = display_text
    ntop_response.display_text = display_text
    ntop_response.suggestions = sugg    
  end

  return ntop_response
end

--#########################################################################################################

function handlers_module.get_single_device_info_from_who_is(user_request)
  local text = ternary( 
        os.time()%2==0 ,
        "Sorry, I didn't understand correctly. Can you repeat, please? ",
        "Sorry I didn't understand what you mean, can you please repeat?"
      )
  local device_name = user_request.queryResult.queryText
  if (not device_name) or (device_name == "") then
    ntop_response.speech_text =  text 
    return ntop_response
  end

  local macs_table_len, macs_table, mac = h_utils.find_mac_hosts(device_name)
  local d_info = {}

  if macs_table_len > 1 then 
    --TODO: metti suggerimenti e diversifica la risposta audio
    text = "I found this, please select one of the suggestions"

  elseif macs_table_len == 1 then 
    d_info = h_utils.merge_hosts_info(macs_table[mac].ip)

    local discover = require "discover_utils"
  
    text = "\tName: ".. d_info.name .. "\nType: "..d_info.devtype_name.."\nManufacturer: ".. d_info.manufacturer
    if d_info.model then text = text .."\nModel: "..d_info.model end
    if d_info.operatingSystem then text = text .."\nOS: "..getOsName(d_info.operatingSystem) end
    if d_info.ndpi then text = text .. "\nMost used app: "..d_info.ndpi[1].name end
    if d_info.ndpi_categories then text = text .. "\nMost traffic belong to category: "..d_info.ndpi_categories[1].name end

  end
  --TODO: salva un qualche id (mac + i vari host ip? non sarebbe male) del device. serve per il followup intent "more"
  ntop.setCache("nAssistant_device_info_mac", mac, 60*20 ) -- 20 min tempo max di vita

  ntop_response.speech_text =  text 
  return ntop_response
end

--#########################################################################################################

--NOTE: gli alert flow sono un sottoinsieme dei misbehaving flow! dentro mis_flows si distinguono per ladescrizione che inizia con "alerts_dashboard..." 
function handlers_module.get_security_info(user_request)
  local g_domain, mis_flows = net_state.get_interface_ghost_network(), net_state.get_hosts_flow_misbehaving_stats()
  local display_text = ""  
  local sugg = {}

  if table.len(g_domain) > 0 then
    display_text = display_text .. table.len(g_domain).. " ghost networks detected.\n"
    table.insert(sugg, "ghost network")
  end

  if table.len(mis_flows) > 0 then
    display_text = display_text .. table.len(mis_flows).. " suspected hosts for misbehaving, these are the most relevant.\n"
    table.insert(sugg,"most misbehaving host")
  end

  if table.len(g_domain) + table.len(mis_flows) == 0 then
    ntop_response.speech_text = "The network is secure!\nNothing suspicious detected"
    return ntop_response
  end

  local legend_label = "Hosts Score"
  local data = {labels = {}, datasets = { data = {} }}
  local options = { 
      w = "500",
      h = "280",
      chart_type = "outlabeledPie", 
      bkg_color = "white",
      outlabels_text = "ip: %l (%p)\nThreatScore: %v ",
      show_legend = false
  }

  for _, v in pairs(mis_flows) do
      
    if string.len(v.addr) > label_max_len then 
      table.insert(data.labels,  string.sub(v.addr,1,label_max_len) .. "..." )
    else 
      table.insert(data.labels,  v.addr)
    end
    table.insert(data.datasets.data, v.score)
    table.insert(sugg, v.addr)

    if table.len(sugg) > (limit_num_top_host-1) then break end  --TODO: the -1 is temporary! remove after the labels fix
  end

  local url = df_utils.create_chart_url(data, options)
  local image =  {img_url = url, img_description = "misbehaving hosts score chart" }
  local opt = { title ="Top Misbehaving hosts"}
  local card = dialogflow.create_card(nil, image, opt  )

  ntop_response.speech_text = display_text
  ntop_response.display_text = display_text
  ntop_response.suggestions = sugg    
  ntop_response.card = card

  return ntop_response  
end

--#########################################################################################################

--lui è praticamente una copia di host_info_more - security relativa al "peggior" host
-- è una shortcut in pratica che permette di accedere a tali info solo con comandi vocali e velocemente
function handlers_module.get_most_suspected_host_info(user_request)
  local flow_consts = require "flow_consts"
  local mis_flows = net_state.get_hosts_flow_misbehaving_stats()

  local legend_label = "Suspect activities"
  local data = {labels = {}, datasets = { data = {} }}
  local options = { 
    w = "500",
    h = "300",
    chart_type = "outlabeledPie", 
    bkg_color = "white",
    outlabels_text = "ThreatScore: %v ",
    --show_legend = false
    legend_labels_font_size = 12,
    outlabels_stretch = 17
  }

  local i = 1
  local status_txt = ""
  local max_score_flow = {score = 0}

  local score

  for status_id, v in pairs(mis_flows[1].status) do  
    status_txt = flow_consts.flow_status_types[status_id].i18n_title 

    status_txt = string.gsub(status_txt, "flow_details.", "") 
    status_txt = string.gsub(status_txt, "alerts_dashboard.", "[!] ") 
    status_txt = string.gsub(status_txt, "_", " ") 

    score = flow_consts.flow_status_types[status_id].relevance * v

    table.insert(data.datasets.data, score )
    table.insert(data.labels,  status_txt)

    if max_score_flow.score < score then 
      max_score_flow.id = status_id
      max_score_flow.score = score
      max_score_flow.descr = string.gsub(status_txt, "[!] ", "") --TODO: fix!!! "[!]" not removed
    end

    if table.len(labels) == limit_num_top_host then break end
  end

  local sugg = table.merge(data.labels,  {"more applications", "more categories", "more network" } )
  local url = df_utils.create_chart_url(data, options)
  local image =  {img_url = url, img_description = "misbehaving host chart" }
  local opt = { title = "Most Misbehaving Host"}
  local card = dialogflow.create_card(nil, image, opt  )
  
  local display_text = getHostAltName( mis_flows[1].addr)
  if getHostAltName( mis_flows[1].addr) ~= mis_flows[1].addr then 
    display_text = display_text .. "  (".. mis_flows[1].addr..")"
  end

  ntop.setCache("nAssistant_misbehaving_host_ip", mis_flows[1].addr, 60*20 )

  local speech_text = "The host has generated ".. mis_flows[1].flow_counter.." suspected flow in total."..
                      "The most dangerous seems to be: \""..max_score_flow.descr.."\" with a score of ".. max_score_flow.score..
                      " based on ".. mis_flows[1].status[max_score_flow.id].. " flows of that type."

  ntop_response.speech_text = speech_text
  ntop_response.display_text = display_text
  ntop_response.suggestions = sugg    
  ntop_response.card = card

  return ntop_response
end

--#########################################################################################################

--TODO: non sarebbe male mettere info specifiche dentro "status" in network_state.get_hosts_flow_misbehaving_stats()
      --con quelle info potrei dire belle cosine! guarda su ntopng dettagli/descrizioni riguardo ad ogni mis_flow

function handlers_module.get_host_misbehaving_flows_info(user_request)
  local flow_consts = require "flow_consts"

  local flow_id = tonumber(user_request.queryResult.parameters.flow_status)
  local host_ip = ntop.getCache("nAssistant_misbehaving_host_ip")
  if not (host_ip and flow_id) then
    ntop_response.speech_text = "Ops, I can't find the flow, ask me something else" 
    return ntop_response
  end
  local mis_flows = net_state.get_hosts_flow_misbehaving_stats()
  local host_mis_flows = nil
  local host = interface.getHostInfo(host_ip)

  for i,v in ipairs(mis_flows)do
    if v.addr == host_ip then host_mis_flows = v end
  end
  if not (host_mis_flows and host) then
    ntop_response.speech_text = "Ops, I can't find the host, ask me something else" 
    return ntop_response
  end

  --note: tenere chart in sync con host_info_more - security
  --note: c'è sempre il chart perché me lo porto dietro da "host_info_more - security"
  local speech_text, display_text, sugg, card = "test", "test", {}, {}
  local chart_description = "host misbehaving flow" --note: no title
  local data = {labels = {}, datasets = { data = {} }}
  local options = { 
    w = "500",
    h = "300",
    chart_type = "outlabeledPie", 
    bkg_color = "white",
    outlabels_text = "ThreatScore: %v ",
    legend_labels_font_size = 12,
    outlabels_stretch = 17
  }
  local card_opt, card_text = nil, nil --uso per il weblink della JA3 in malicious_signature

  local mis_flow_counter = host_mis_flows.status[flow_id]
  local score = flow_consts.flow_status_types[flow_id].relevance * mis_flow_counter
  --local tot_mis_flows_bytes = host_mis_flows.bytes
  local flow_description = string.gsub(flow_consts.flow_status_types[flow_id].i18n_title, "alerts_dashboard.", "") 
  flow_description = string.gsub(flow_description, "_", " ")

  local num_tot_flows = 0
  for i,v in pairs(host_mis_flows.status) do
    num_tot_flows = num_tot_flows +  v
  end

  if     flow_id == flow_consts.status_slow_tcp_connection then
  elseif flow_id == flow_consts.status_slow_application_header then
  elseif flow_id == flow_consts.status_slow_data_exchange then
  elseif flow_id == flow_consts.status_low_goodput then ------------------done

    display_text = "The host "..
          ternary(getHostAltName(host_ip) ~= host_ip," named ".. getHostAltName(host_ip)..",", "" )..
          " has generated ".. host_mis_flows.status[flow_id].. " slow flows out of"..num_tot_flows

    speech_text =  "The host has generated ".. host_mis_flows.status[flow_id].. " slow flows out of "..num_tot_flows

    local status_txt = ""    
    for status_id, v in pairs(host_mis_flows.status) do  
      status_txt = flow_consts.flow_status_types[status_id].i18n_title 
      status_txt = string.gsub(status_txt, "flow_details.", "") 
      status_txt = string.gsub(status_txt, "alerts_dashboard.", "[!] ") 
      status_txt = string.gsub(status_txt, "_", " ") 
  
      score = flow_consts.flow_status_types[status_id].relevance * v
      table.insert(data.datasets.data, score )
      table.insert(data.labels,  status_txt)

      if table.len(labels) == limit_num_top_host then break end
    end  
    sugg = table.merge(  data.labels, {"more applications", "more categories", "more security" } )
          
  elseif flow_id == flow_consts.status_suspicious_tcp_syn_probing then
  elseif flow_id == flow_consts.status_tcp_connection_issues then
  elseif flow_id == flow_consts.status_suspicious_tcp_probing then  ---------------done

    display_text = "The host "..
          ternary(getHostAltName(host_ip) ~= host_ip," named ".. getHostAltName(host_ip)..",", "" )..
          " has generated ".. host_mis_flows.status[flow_id].. " flows suspected of TCP probing, out of"..num_tot_flows

    speech_text =  "The host has generated ".. host_mis_flows.status[flow_id].. " flows suspected of TCP probing, out of "..num_tot_flows

    local status_txt = ""    
    for status_id, v in pairs(host_mis_flows.status) do  
      status_txt = flow_consts.flow_status_types[status_id].i18n_title 
      status_txt = string.gsub(status_txt, "flow_details.", "") 
      status_txt = string.gsub(status_txt, "alerts_dashboard.", "[!] ") 
      status_txt = string.gsub(status_txt, "_", " ") 
  
      score = flow_consts.flow_status_types[status_id].relevance * v
      table.insert(data.datasets.data, score )
      table.insert(data.labels,  status_txt)

      if table.len(labels) == limit_num_top_host then break end
    end 
    sugg = table.merge(  data.labels, {"more applications", "more categories", "more security" } )
          
  elseif flow_id == flow_consts.status_flow_when_interface_alerted then
  elseif flow_id == flow_consts.status_tcp_connection_refused then  ---------------done

    display_text = "The host "..
          ternary(getHostAltName(host_ip) ~= host_ip," named ".. getHostAltName(host_ip)..",", "" )..
          " has generated ".. host_mis_flows.status[flow_id].. " flows which the connection was refused, out of"..num_tot_flows

    speech_text =  "The host has generated ".. host_mis_flows.status[flow_id].. " flows which the connection was refused, out of "..num_tot_flows

    local status_txt = ""    
    for status_id, v in pairs(host_mis_flows.status) do  
      status_txt = flow_consts.flow_status_types[status_id].i18n_title 
      status_txt = string.gsub(status_txt, "flow_details.", "") 
      status_txt = string.gsub(status_txt, "alerts_dashboard.", "[!] ") 
      status_txt = string.gsub(status_txt, "_", " ") 
  
      score = flow_consts.flow_status_types[status_id].relevance * v
      table.insert(data.datasets.data, score )
      table.insert(data.labels,  status_txt)

      if table.len(labels) == limit_num_top_host then break end
    end 
    sugg = table.merge(  data.labels, {"more applications", "more categories", "more security" } )
 
  elseif flow_id == flow_consts.status_ssl_certificate_mismatch then
  elseif flow_id == flow_consts.status_dns_invalid_query then
  elseif flow_id == flow_consts.status_remote_to_remote then
  elseif flow_id == flow_consts.status_blacklisted then 
  elseif flow_id == flow_consts.status_blocked then
  elseif flow_id == flow_consts.status_web_mining_detected then
  elseif flow_id == flow_consts.status_device_protocol_not_allowed then
  elseif flow_id == flow_consts.status_elephant_local_to_remote then
  elseif flow_id == flow_consts.status_elephant_remote_to_local then
  elseif flow_id == flow_consts.status_longlived then
  elseif flow_id == flow_consts.status_not_purged then
  elseif flow_id == flow_consts.status_ids_alert then
  elseif flow_id == flow_consts.status_tcp_severe_connection_issues then
  elseif flow_id == flow_consts.status_ssl_unsafe_ciphers then
  elseif flow_id == flow_consts.status_data_exfiltration then
  elseif flow_id == flow_consts.status_ssl_old_protocol_version then
  elseif flow_id == flow_consts.status_potentially_dangerous then   ---------------done

    display_text = "The host "..
    ternary(getHostAltName(host_ip) ~= host_ip," named ".. getHostAltName(host_ip)..",", "" )..
    " has generated ".. host_mis_flows.status[flow_id].. " flows with potentially dangerous protocol, out of"..num_tot_flows

    speech_text =  "The host has generated ".. host_mis_flows.status[flow_id].. " flows with potentially dangerous protocol, out of "..num_tot_flows

    local status_txt = ""    
    for status_id, v in pairs(host_mis_flows.status) do  
      status_txt = flow_consts.flow_status_types[status_id].i18n_title 
      status_txt = string.gsub(status_txt, "flow_details.", "") 
      status_txt = string.gsub(status_txt, "alerts_dashboard.", "[!] ") 
      status_txt = string.gsub(status_txt, "_", " ") 

      score = flow_consts.flow_status_types[status_id].relevance * v
      table.insert(data.datasets.data, score )
      table.insert(data.labels,  status_txt)

      if table.len(labels) == limit_num_top_host then break end
    end
    
    sugg = table.merge(  data.labels, {"more applications", "more categories", "more security" } )

  elseif flow_id == flow_consts.status_malicious_signature then     ---------------done 

    local ja3 = ""
    
    for h,v in pairs(host["ja3_fingerprint"]) do -- assuming only one ja3 fingerprint
      ja3 = h;break
    end
   
    speech_text = "The host "..
          --ternary(getHostAltName(host_ip) ~= host_ip," named ".. getHostAltName(host_ip)..",", "" )..
          "has generated ".. host_mis_flows.status[flow_id].. " flows"..
          " with a blacklisted fingerprint.\nFor further information follow the link below."

    display_text =  "Host: "..host_ip..
          ternary(getHostAltName(host_ip) ~= host_ip," named ".. getHostAltName(host_ip), "" )..
          ".\nFlow with malicious signature: "..  host_mis_flows.status[flow_id]

    local status_txt = ""    
    for status_id, v in pairs(host_mis_flows.status) do  
      status_txt = flow_consts.flow_status_types[status_id].i18n_title 
      status_txt = string.gsub(status_txt, "flow_details.", "") 
      status_txt = string.gsub(status_txt, "alerts_dashboard.", "[!] ") 
      status_txt = string.gsub(status_txt, "_", " ") 
  
      score = flow_consts.flow_status_types[status_id].relevance * v
      table.insert(data.datasets.data, score )
      table.insert(data.labels,  status_txt)

      if table.len(labels) == limit_num_top_host then break end
    end 
  
    --note: in sugg dovrei inserire al massimo 7 labels (cioè 12, il max numero, meno i 5 "more")  
    sugg = table.merge(  data.labels, {"more applications", "more categories", "more security" } )
    local url = "https://sslbl.abuse.ch/ja3-fingerprints/"..ja3
    card_opt = { weblink_title = "JA3", weblink = url}  --no title?
    card_text = "SSL blacklist, by abuse:"
          
  else speech_text = "Ops, there is a problem with the flow status, try later!"
  end

  local url = df_utils.create_chart_url(data, options)
  local image =  {img_url = url, img_description = chart_description }
  local opt = card_opt or { title = card_title}
  local card = dialogflow.create_card(card_text, image, opt  )   
  ntop_response.card = card

  ntop_response.speech_text = speech_text
  ntop_response.display_text = display_text
  ntop_response.suggestions = sugg    
  ntop_response.card = card

  return ntop_response  
end

--#########################################################################################################

  --[[
      throughput_pps number 0.0
      childSafe boolean false
      seen.last number 1561247422
      tcp.bytes.sent number 319255
      other_ip.bytes.sent.anomaly_index number 0
      bytes.rcvd number 35100
      low_goodput_flows.as_client number 0
      has_dropbox_shares boolean false
      tcp.bytes.rcvd number 35100
      packets.sent.anomaly_index number 0
      tcp.bytes.rcvd.anomaly_index number 0
      operatingSystem number 0
      devtype number 0
      packets.sent number 327
      icmp.bytes.sent.anomaly_index number 0
      hiddenFromTop boolean false
      flows.as_client number 6
      udpBytesSent.non_unicast number 0
      systemhost boolean false
      tcpPacketStats.sent table
      tcpPacketStats.sent.keep_alive number 0
      tcpPacketStats.sent.out_of_order number 0
      tcpPacketStats.sent.lost number 1
      tcpPacketStats.sent.retransmissions number 0
      num_alerts number 0
      num_flow_alerts number 7
      flows.as_server number 17
      bytes.sent number 319255
      throughput_trend_bps number 0
      mac string 00:0C:31:EC:67:98
      hassh_fingerprint table
      other_ip.packets.rcvd number 0
      broadcast_domain_host boolean false
      ifid number 4
      tcpPacketStats.rcvd table
      tcpPacketStats.rcvd.keep_alive number 0
      tcpPacketStats.rcvd.out_of_order number 1
      tcpPacketStats.rcvd.lost number 1
      tcpPacketStats.rcvd.retransmissions number 0
      duration number 163
      bytes.rcvd.anomaly_index number 0
      udp.packets.sent number 0
      privatehost boolean false
      hits.syn_flood_victim number 1
      active_alerted_flows number 7
      os_detail string 
      num_triggered_alerts table
      num_triggered_alerts.day number 0
      num_triggered_alerts.hour number 0
      num_triggered_alerts.min number 0
      num_triggered_alerts.5mins number 0
      low_goodput_flows.as_server.anomaly_index number 0
      low_goodput_flows.as_client.anomaly_index number 0
      active_flows.as_client number 6
      city string 
      name string 
      longitude number 0.0
      latitude number 0.0
      country string 
      continent string 
      udp.bytes.sent.anomaly_index number 0
      other_ip.bytes.rcvd.anomaly_index number 0
      names table
      ja3_fingerprint table
      throughput_trend_pps number 0
      unreachable_flows.as_client number 0
      tcp.packets.rcvd number 253
      drop_all_host_traffic boolean false
      total_activity_time number 5
      localhost boolean false
      is_multicast boolean false
      unreachable_flows.as_server number 0
      contacts.as_server number 0
      icmp.bytes.rcvd.anomaly_index number 0
      os number 0
      contacts.as_client number 0
      anomalous_flows_status_map.as_client number 128
      anomalous_flows_status_map.as_server number 134217744
      active_flows.as_server number 17
      low_goodput_flows.as_server number 0
      pktStats.recv table
      pktStats.recv.upTo1518 number 0
      pktStats.recv.finack number 7
      pktStats.recv.rst number 4
      pktStats.recv.upTo1024 number 22
      pktStats.recv.synack number 0
      pktStats.recv.upTo6500 number 0
      pktStats.recv.upTo256 number 14
      pktStats.recv.above9000 number 0
      pktStats.recv.upTo9000 number 0
      pktStats.recv.upTo128 number 18
      pktStats.recv.syn number 18
      pktStats.recv.upTo512 number 5
      pktStats.recv.upTo2500 number 0
      pktStats.recv.upTo64 number 194
      anomalous_flows.as_server number 8
      icmp.bytes.sent number 0
      icmp.packets.sent number 0
      bytes.sent.anomaly_index number 0
      active_http_hosts number 0
      other_ip.bytes.sent number 0
      other_ip.packets.sent number 0
      host_pool_id number 0
      bytes.ndpi.unknown number 0
      tskey string 35.226.156.55
      host_unreachable_flows.as_client number 0
      tcp.bytes.sent.anomaly_index number 0
      asn number 0
      ip string 35.226.156.55
      icmp.packets.rcvd number 0
      ndpi table
      ndpi.TLS table
      ndpi.TLS.duration number 5
      ndpi.TLS.packets.sent number 136
      ndpi.TLS.breed string Safe
      ndpi.TLS.num_flows number 0
      ndpi.TLS.packets.rcvd number 121
      ndpi.TLS.bytes.rcvd number 12546
      ndpi.TLS.bytes.sent number 125624
      ndpi.HTTP table
      ndpi.HTTP.duration number 5
      ndpi.HTTP.packets.sent number 191
      ndpi.HTTP.breed string Acceptable
      ndpi.HTTP.num_flows number 0
      ndpi.HTTP.packets.rcvd number 132
      ndpi.HTTP.bytes.rcvd number 22554
      ndpi.HTTP.bytes.sent number 193631
      udpBytesSent.unicast number 0
      udp.bytes.rcvd number 0
      udp.packets.rcvd number 0
      other_ip.bytes.rcvd number 0
      seen.first number 1561247260
      tcp.packets.sent number 327
      total_alerts number 7
      host_unreachable_flows.as_server number 0
      pktStats.sent table
      pktStats.sent.upTo1518 number 193
      pktStats.sent.finack number 0
      pktStats.sent.rst number 6
      pktStats.sent.upTo1024 number 32
      pktStats.sent.synack number 17
      pktStats.sent.upTo6500 number 0
      pktStats.sent.upTo256 number 10
      pktStats.sent.above9000 number 0
      pktStats.sent.upTo9000 number 0
      pktStats.sent.upTo128 number 5
      pktStats.sent.syn number 0
      pktStats.sent.upTo512 number 11
      pktStats.sent.upTo2500 number 0
      pktStats.sent.upTo64 number 76
      tcp.packets.seq_problems boolean true
      packets.rcvd.anomaly_index number 0
      udp.bytes.rcvd.anomaly_index number 0
      anomalous_flows.as_client number 6
      total_flows.as_server number 17
      throughput_bps number 0.0
      udp.bytes.sent number 0
      packets.rcvd number 253
      total_flows.as_client number 6
      ndpi_categories table
      ndpi_categories.Web table
      ndpi_categories.Web.duration number 5
      ndpi_categories.Web.bytes.rcvd number 35100
      ndpi_categories.Web.bytes number 354355
      ndpi_categories.Web.bytes.sent number 319255
      ndpi_categories.Web.category number 5
      score number -1
      is_broadcast boolean false
      asname string 
      vlan number 0
      icmp.bytes.rcvd number 0
      dhcpHost boolean false
      ipkey number 602053687
      is_blacklisted boolean false

  ]]

function handlers_module.host_info(user_request)
  local text = "I don't get it, can you repeat please?"
  local host_name = user_request.queryResult.queryText
  if (not host_name) or (host_name == "") then
    ntop_response.speech_text =  text 
    return ntop_response
  end

  --TODO: FIND HOST BY QUERY, o almeno un modo per far selezionare l'host all'utente
  local host_info, sugg = interface.getHostInfo(host_name), {}
  
  --note: provvisorio
  if not host_info then 
    ntop_response.speech_text = text
    return ntop_response
  end
  ntop.setCache("nAssistant_host_info_ip", host_name , 60*20 )--metto in cache per il followup-more
  sugg = {"more applications", "more categories", "more network", "more security", "more host info" }

  local alias = ""
  if not host_info.name or host_info.name == "" then host_info.name = host_info.ip end 
  
  if  host_info.name and host_info.name ~= ""  and getHostAltName(host_info.ip) ~= host_info.name then 
    alias = " [".. getHostAltName(host_info.ip) .." ]"
  end

  local discover = require "discover_utils"

  local num_triggered_alerts = 0
  for i,v in pairs(host_info.num_triggered_alerts) do
    num_triggered_alerts = num_triggered_alerts + v
  end

  text = "\tHost: ".. host_info.name..ternary( alias ~= "", "("..alias..")", "" ).."\n"
        ..ternary( host_info.is_blacklisted, "The host is blacklisted.\n", "" )
        ..ternary(host_info.num_alerts + num_triggered_alerts + host_info.num_flow_alerts > 0,
                   host_info.num_alerts.." Host alerts ("..num_triggered_alerts.." triggered), "..host_info.num_flow_alerts.." flow alerts.\n", "" )
        ..ternary(host_info.os ~= 0, "OS: "..discover.getOsName(host_info.os).."\n" , "" )
        ..ternary(host_info.devtype ~= 0, "The host is a "..discover.devtype2string(host_info.devtype).."\n" , "" )

  local mac_info = interface.getMacInfo(host_info.mac)
  --tprint(mac_info)
  if mac_info then 
    text = text ..ternary(mac_info.manufacturer , "Manufacturer "..mac_info.manufacturer.."\n" , "" )
        --  ..ternary(mac_info.model, "Model "..mac_info.model.."\n" , "" )
  end

  ntop_response.speech_text = "Here you have some info about the host"
  ntop_response.display_text = text
  ntop_response.suggestions = sugg    

  return ntop_response
end

--#########################################################################################################

--TODO: in categories e applications chart, crea il gruppo "other" in cui metto i proto/cat con le percentuali basse
function handlers_module.host_info_more(user_request)
  local info_type = user_request.queryResult.parameters.host_info--note: info type = general - applications - security - categories - network
  local ip = ntop.getCache("nAssistant_host_info_ip")

  local host_info = interface.getHostInfo(ip)
  local is_chart = false
  local speech_text, display_text = "test", "test"  --TODO: provvisorio, fai a modo

  local sugg = {"more applications", "more categories", "more network", "more security", "more host info" }

  if not host_info then 
    ntop_response.speech_text = "Can't find the host address! Please ask me something else" 
    return ntop_response
  end

  if not host_info.name or host_info.name == "" then host_info.name = getHostAltName( host_info.ip) end
  if not host_info.name or host_info.name == "" then host_info.name = host_info.ip end

  --TODO: usa una sorta di manager (factory) per i chart
  local labels, values, datasets = {},{},{}
  local legend_label = "Traffic (KB)"
  local data = {labels = {}, values = {}, legend_label = legend_label}
  local options = { 
    w = "600",
    h = "320",
    chart_type = "outlabeledPie", 
    bkg_color = "white",
    outlabels_text = "%l\n%v KB (%p) ",
    show_legend = false,
    outlabels_stretch = 15
  } 
  local card_title, chart_description = "Chart", "Chart"

  if     info_type == "applications" then ------------------------------------
    if table.len(host_info.ndpi) <= 0 then
      ntop_response.speech_text = "No application detected. Please, ask me something else"
      ntop_response.display_text = "No application detected. Please, ask me something else"
      ntop_response.suggestions = sugg    
      return ntop_response
    end

    is_chart = true
    chart_description = "Top Application for ".. host_info.name 
    card_title = "Top Application for ".. host_info.name 
    local i = 0
    local top_ndpi= {}
    local i = 0

    for p,v in pairs(host_info.ndpi) do
      table.insert(top_ndpi, table.merge( {name = p}, v ) )
      i = i + 1
    end

    table.sort( top_ndpi, function(a,b) return a["bytes.rcvd"]+a["bytes.sent"] > b["bytes.rcvd"]+b["bytes.sent"] end )

    i = 0
    for _,v in ipairs(top_ndpi) do
      table.insert(data.labels, v.name) 
      table.insert(data.values, tonumber(string.format("%.2f", (v["bytes.rcvd"]+v["bytes.sent"])/1024 ))  )
      i = i + 1
      if i >= limit_num_ndpi_proto_chart then break end   
    end

    local len = table.len(top_ndpi)
    local j = 1

    speech_text = "The main application is ".. top_ndpi[1].name
    if len > 1 then
      speech_text = speech_text ..  ", followed by "..top_ndpi[2].name
    end
    if len > 2 then
      speech_text = speech_text ..  " and "..top_ndpi[3].name
    end

    display_text = "Here is the chart"

  elseif info_type == "categories" then    ------------------------------------
    if table.len(host_info.ndpi_categories) <= 0 then 
      ntop_response.speech_text = "No categories detected. Please, ask me something else"
      ntop_response.display_text = "No categories detected. Please, ask me something else"
      ntop_response.suggestions = sugg    
      return ntop_response
    end

    local top_ndpi_cat= {}
    local i = 0

    for p,v in pairs(host_info.ndpi_categories) do
      table.insert(top_ndpi_cat, table.merge( {name = p}, v ) )
      i = i + 1
    end

    table.sort( top_ndpi_cat, function(a,b) return a.bytes > b.bytes end )

    is_chart = true
    chart_description = "Top Categories for ".. host_info.name 
    card_title = "Top Categories for ".. host_info.name

    i = 0
    for name,v in ipairs( top_ndpi_cat) do
      table.insert(data.labels, v.name)
      table.insert(data.values, tonumber(string.format("%.2f", v.bytes/1024)  ) ) --TODO: metti i MB invece dei KB all'occorrenza

      i = i + 1
      if i >= limit_num_ndpi_categories_chart then break end   
    end

    local len = table.len(top_ndpi_cat)

    speech_text = "The main category is ".. top_ndpi_cat[1].name
    if len > 1 then
      speech_text = speech_text .. ", followed by "..top_ndpi_cat[2].name
    end
    if len > 2 then
      speech_text = speech_text ..  " and "..top_ndpi_cat[3].name 
    end
    display_text = nil

  elseif info_type == "security" then   ------------------------------------
    --traffic breed graph:
      -- chart_description = "Traffic Breed for ".. d_info.name 
      -- card_title = "Traffic Breed for ".. d_info.name
      -- local breeds_table = {}
      -- for _,v in ipairs(d_info.ndpi) do
      --   if breeds_table[v.info.breed] then 
      --     breeds_table[v.info.breed] = breeds_table[v.info.breed] + v.info["bytes.rcvd"] + v.info["bytes.sent"]
      --   else
      --     breeds_table[v.info.breed] = v.info["bytes.rcvd"] + v.info["bytes.sent"]
      --   end
      -- end
      -- for ii,v in pairs(breeds_table) do
      --   table.insert(data.labels, ii) 
      --   table.insert(data.values, (v/1024) )
      --   i = i + 1
      --   if i >= 6 then break end    --NOTE: 6 and 1 are arbitrary 
      -- end
      -- speech_text = display_text --TODO: change this, is temporary
    --
    
    local mis_flows = net_state.get_hosts_flow_misbehaving_stats()
    local host_mis_flows = nil

    for i,v in pairs(mis_flows) do 
      if v.addr == ip then 
        host_mis_flows = v
      end
    end

    if not host_mis_flows then --TEST TODO se il break rompe l'if
      ntop_response.speech_text = "No misbehaving flows detected"
      ntop_response.display_text = "No misbehaving flows detected"
      ntop_response.suggestions = sugg    
      return ntop_response
    end

    --cambio le opzioni del chart a causa della dimensione delle labels
    options = { 
      w = "500",
      h = "300",
      chart_type = "outlabeledPie", 
      bkg_color = "white",
      outlabels_text = "ThreatScore: %v ",
      --show_legend = false
      legend_labels_font_size = 12,
      outlabels_stretch = 17
    }

    is_chart = true
    chart_description = "Security for ".. host_info.name --TODO: check e magari metto getHostAltName( host_info.name)
    card_title = "Security for ".. host_info.name --TODO: check e magari metto getHostAltName( host_info.name)
    local flow_consts = require "flow_consts"
    local status_txt = ""
    local max_score_flow = {score = 0}
    local score

    for status_id, v in pairs(host_mis_flows.status) do  
      status_txt = flow_consts.flow_status_types[status_id].i18n_title 
  
      status_txt = string.gsub(status_txt, "flow_details.", "") 
      status_txt = string.gsub(status_txt, "alerts_dashboard.", "[!] ") 
      status_txt = string.gsub(status_txt, "_", " ") 
  
      score = flow_consts.flow_status_types[status_id].relevance * v
  
      table.insert(data.values, score )
      table.insert(data.labels,  status_txt)
  
      if max_score_flow.score < score then 
        max_score_flow.id = status_id
        max_score_flow.score = score
        max_score_flow.descr = string.gsub(status_txt, "[!] ", "") --TODO: fix!!! "[!]" not removed
      end
  
      if table.len(labels) == limit_num_top_host then break end
    end
  
    --TODO: max sugg è 8! tolgiere i mis_flow meno rilevanti? togliere i more? perora ho tolto i more
    local i = 3
    sugg = table.merge(data.labels, {"more applications", "more categories", "more network" })
    --local url = df_utils.create_chart_url(data, options)
    -- image =  {img_url = url, img_description = "misbehaving host chart" }
    -- opt = { title = "Most Misbehaving Host"}
    -- card = dialogflow.create_card(nil, image, opt  )
    
    --cambia mis_flows
    display_text = getHostAltName( host_mis_flows.addr)
    if getHostAltName( host_mis_flows.addr) ~= host_mis_flows.addr then 
      display_text = display_text .. "  (".. host_mis_flows.addr..")"
    end
  
    --serve se poi voglio info sui mis_flow di questo host
    ntop.setCache("nAssistant_misbehaving_host_ip", host_mis_flows.addr, 60*20 )
  
    speech_text = "The host has generated ".. host_mis_flows.flow_counter.." suspected flow in total."..
                  "The most dangerous seems to be: \""..max_score_flow.descr.."\" with a score of ".. max_score_flow.score..
                  " based on ".. host_mis_flows.status[max_score_flow.id].. " flows of that type."
  
    display_text = nil

  elseif info_type == "network" then ------------------------------------

    --TODO: goodput, tcpPktStats per l'efficienza, 
    --TODO: sempre i vari check sulle tabelle prima di iterarci
    --TODO:  elencare LE interfacce attive
    -- local if_name = interface.getIfNames()[d_info.ifid]

    display_text = "Interface Name = "..ifname.."\nAddresses:\nIP = "..host_info.ip.."\n"..
          ternary(host_info.mac , "MAC = "..host_info.mac.."\n" , "" )

    -- local mac_info = interface.getMacInfo(host_info.ip)
    -- if mac_info and mac_info.mac then
    --   display_text = display_text .."MAC: "..mac_info.mac.."\n"
    -- end

    display_text = display_text .. "\nApplications Traffic Volume(KB):\n\tsent/rcvd = "..
      string.format("%.2f",host_info["bytes.sent"]/1024).." / "..string.format("%.2f",host_info["bytes.rcvd"]/1024)

    speech_text = "Here you have some technical information"

  elseif info_type == "general" then ------------------------------------

      if not host_info then 
        ntop_response.speech_text = "I don't get it, can you repeat please?"
        return ntop_response
      end    
      local alias = ""
      if not host_info.name or host_info.name == "" then host_info.name = host_info.ip end 
      
      if  host_info.name and host_info.name ~= ""  and getHostAltName(host_info.ip) ~= host_info.name then 
        alias = " [".. getHostAltName(host_info.ip) .." ]"
      end
    
      local discover = require "discover_utils" 
      local num_triggered_alerts = 0
      for i,v in pairs(host_info.num_triggered_alerts) do
        num_triggered_alerts = num_triggered_alerts + v
      end
    
      text = "\tHost: ".. host_info.name..ternary( alias ~= "", "("..alias..")", "" ).."\n"
            ..ternary( host_info.is_blacklisted, "The host is blacklisted.\n", "" )
            ..ternary(host_info.num_alerts + num_triggered_alerts + host_info.num_flow_alerts > 0,
                       host_info.num_alerts.." Host alerts ("..num_triggered_alerts.." triggered), "..host_info.num_flow_alerts.." flow alerts.\n", "" )
            ..ternary(host_info.os ~= 0, "OS: "..discover.getOsName(host_info.os).."\n" , "" )
            ..ternary(host_info.devtype ~= 0, "The host is a "..discover.devtype2string(host_info.devtype).."\n" , "" )
    
      local mac_info = interface.getMacInfo(host_info.mac)
      --tprint(mac_info)
      if mac_info then 
        text = text ..ternary(mac_info.manufacturer ~= nil , "Manufacturer "..mac_info.manufacturer.."\n" , "" )
            --  ..ternary(mac_info.model, "Model "..mac_info.model.."\n" , "" )
      end
      speech_text = "Here you have some info about the host"
      display_text = text
  end 

  if is_chart then 
    local url = df_utils.create_chart_url(data, options)
    local image =  {img_url = url, img_description = chart_description }
    local opt = { title = card_title}
    local card = dialogflow.create_card(nil, image, opt  )   
    ntop_response.card = card
  end
  ntop_response.speech_text = speech_text
  ntop_response.display_text = display_text
  ntop_response.suggestions = sugg    

  return ntop_response
end

return handlers_module

