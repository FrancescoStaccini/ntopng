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
local json = require("dkjson")
local df_utils = require("dialogflow_utils")

local response, request

--TODO: CANCELLA I VECCHI FILE: google_assistant_utils.lua ecc.

--##########################################-nAssistant-utils-############################################################

local function handler_get_aggregated_info_traffic()
  local stats, text = net_state.check_net_communication(),""
  local ctg, prc = net_state.check_top_traffic_application_protocol_categories()

  if stats.prc_remote2local_traffic + stats.prc_local2remote_traffic < 50 then
    text = text .. "Traffic is mainly internal to the network "
  elseif stats.prc_remote2local_traffic > stats.prc_local2remote_traffic then 
    text = text .. "Most of the data traffic comes from outside the network, "
  else 
    text = text .. "Traffic is mostly directed outside of the network, "
  end

  text = text .. " of which "..prc.." percentage is "..ctg..". Data transmission efficiency is "
  --TODO: sistema l'inglese
  
  local perc, state = net_state.check_TCP_flow_goodput_2(), ""
  
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


local function handler_get_aggregated_info_devices()
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
    bl_num_txt = blacklisted_host_num .. "unwanted hosts.\n"
  end

  text = bl_num_txt .. " The communication "..safe_text

  if danger then text = text .. ". \nBut be careful! Dangerous traffic has been detected! " end

  return text
end
  
--#########################################################################################################

local function handler_get_aggregated_info_network()
  local stats = net_state.check_ifstats_table()
  local alert_num, severity = net_state.check_num_alerts_and_severity()
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

function handler_get_aggregated_info_generic()
  local stats = net_state.check_ifstats_table()
  local alert_num, severity = net_state.check_num_alerts_and_severity()
  local top_app = net_state.check_top_application_protocol()
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
    text = text .. " Traffic is mostly ".. top_category[1].name
  end

  if top_app and top_app[1] then 
    text = text .. " and the most talky application is ".. top_app[1][1]..".\n"
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

function handler_get_aggregated_info()
    local response_text = ""
    local tips = {}

    --prendo i param per vedere se è Devices, Network, Traffic, Generic
    local aggregator = request.parameters.Aggregators

    --gestisco i 4 differenti casi
    if aggregator == "Generic" then --mega overview
        response_text = handler_get_aggregated_info_generic()

    elseif aggregator == "Traffic" then --traffic / communication
        response_text = handler_get_aggregated_info_traffic()

    elseif aggregator == "Network" then -- security (bad host, dangerous flow)/ alarm 
        response_text = handler_get_aggregated_info_network()

    elseif aggregator == "Devices" then --devices/hosts
        response_text = handler_get_aggregated_info_devices()
    
    else
         --[[fallback]]
         --non credo ci sia bisogno di implementare una fallback apposita per aggregated_info
    end

    dialogflow.send(response_text)
end


--return an overview of the top ndpi_application regarding the active flows
function handler_if_active_flow_top_application()
    local top_app = net_state.check_top_application_protocol()
    --note: top app is in decrescent order and contain, for each proto, [name-percent-bytes]
    if not top_app then 
        dialogflow.send("I have not found any active communication! Please try again later")
        return
    end
    local labels, values, datasets = {},{},{}
    local legend_label = "Traffic (KB)"
    local data = {labels = {}, values = {}, legend_label = legend_label}
    local options = { 
        w = "500",
        h = "280",
        chart_type = "bar",
        bkg_color = "white"
    }
    local i = 0
    for _,v in ipairs(top_app) do
        table.insert(data.labels, v[1])
        table.insert(data.values, v[3]/1024 ) --TODO: se necessario (tanto traffico) metti i MB invece dei KB
        i = i + 1
        if i > 6 or v[2] < 1 then break end    --NOTE: 6 and 1 are arbitrary
        --TODO: better guard, eg: if perc < X break
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

function handler_get_aggregated_info_more()
  local response_text = ""
  local tips = {}

  local aggregator = request.parameters.Aggregators

  if aggregator == "Generic" then 
      response_text = handler_get_aggregated_info_generic()

  elseif aggregator == "Traffic" then 
      response_text = handler_get_aggregated_info_traffic()

  elseif aggregator == "Network" then 
      response_text = handler_get_aggregated_info_network()

  elseif aggregator == "Devices" then 
      response_text = handler_get_aggregated_info_devices()
  else
       --[[fallback]]
       --non credo ci sia bisogno di implementare una fallback apposita per "aggregated_info - more"
  end

  dialogflow.send(response_text)
end


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
      w = "500",
      h = "280",
      chart_type = "bar",
      bkg_color = "white"
  }
  local i = 0
  for _,v in ipairs(top_cat) do
      table.insert(data.labels, v.name)
      table.insert(data.values, v.bytes/1024 ) --TODO: se necessario (tanto traffico) metti i MB invece dei KB
      i = i + 1
      if i > 6 or v.perc < 1 then break end    --NOTE: 6 and 1 are arbitrary
  end

  local url = df_utils.create_chart_url(data, options)
  local card = dialogflow.create_card(
      "Top Application Chart",
      url,
      "Top Application Chart"
  )
  --local speech_text = df_utils.create_top_categories_speech_text(top_cat)
  local display_text = "Here is the chart"

  --dialogflow.send(speech_text, display_text, nil, nil, card)
  dialogflow.send(display_text, nil, nil, nil, card)
end

--########################################################-Intents-Dispatcher-####################################################################
request = dialogflow.receive()

--get_aggregated_info può ricevere 4 parametri (Devices, generic, Network, Traffic)
--TODO: fai gli adeguati distinguo per i 4 casi
if      request.intent_name == "get_aggregated_info" then response = handler_get_aggregated_info()
elseif  request.intent_name == "get_aggregated_info - repeat" then response = handler_get_aggregated_info() --TODO: fai il repeat per tutti (che abbia senso)
elseif  request.intent_name == "get_aggregated_info - more" then response = handler_get_aggregated_info_more() --TODO: fai il repeat per tutti (che abbia senso)


--questo intent si differenzia dal "get_aggregated_info --> traffic" perché riguarda solo le applicazioni
--check: ha senso accorparli nello stesso intent? stile get_aggregated_info, creando un'antità per distinguere apps/categories
elseif  request.intent_name == "if_active_flow_top_application" then response = handler_if_active_flow_top_application()

elseif  request.intent_name == "if_active_flow_top_categories"  then response = handler_if_active_flow_top_categories()


  

else response = dialogflow.send("Sorry, but I didn't understand, can you repeat?") 
end