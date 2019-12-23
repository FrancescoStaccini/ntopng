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

--#########################################################################################################
local ntop_response = {}

local label_max_len = 18
local limit_num_host_category_chart = 4
local limit_num_host_protocol_chart = 4
local limit_num_chart_top_categories  = 6
local limit_num_suggestions = 12
local limit_num_top_host = 5
local limit_num_ndpi_proto_chart = 6
local limit_num_ndpi_categories_chart = 6

local handlers_module = {}

--#########################################################################################################

function handlers_module.if_active_flow_top_application(user_request)
    local top_app, sugg = net_state.check_top_application_protocol(), {}
    --note: top app is in decrescent order and contain, for each proto, [name-percent-bytes]
    if not top_app then 
        ntop_response.speech_text = "I have not found any active communication! Please try again later"
        return ntop_response
    end

    local data = {labels = {}, values = {}--[[, legend_label = legend_label]]}
    local options = { 
      w = "550",
      h = "300",
      chart_type = "outlabeledPie", 
      bkg_color = "white",
      outlabels_text = "%l %v KB",
      legend_labels_font_size = 12,
      outlabels_stretch = 15,
      show_legend = false
    }
    local i = 0
    for _,v in ipairs(top_app) do
        table.insert(data.labels, v.name)
        table.insert(data.values,  tonumber(string.format("%.2f", v.bytes/1024)) )
        table.insert(sugg, "who is in "..v.name)
        i = i + 1
        if i >= limit_num_top_host or v.percentage < 1 then break end    
    end

    local url = df_utils.create_chart_url(data, options)
    local image =  {img_url = url,img_description = "Top Application Chart" }
    local opt = { title = "Top Application Chart" }
    local card = dialogflow.create_card(nil, image, opt  )
    local speech_text = df_utils.create_top_traffic_speech_text(top_app)

    ntop_response.speech_text = speech_text
    ntop_response.display_text = speech_text
    ntop_response.card = card
    ntop_response.suggestions = sugg 

    return ntop_response
end

--#########################################################################################################

function handlers_module.if_active_flow_top_categories(user_request)
  local top_cat, sugg = net_state.check_traffic_categories(), {}
  --note: top app is in decrescent order and contain, for each caregory, [name-perc-bytes]
  if not top_cat then 
      ntop_response.speech_text = "I have not found any active communication! Please try again later"
      return ntop_response
  end
  local data = {labels = {}, values = {}--[[, legend_label = legend_label]]}
  local options = { 
    w = "550",
    h = "300",
    chart_type = "outlabeledPie", 
    bkg_color = "white",
    outlabels_text = "%l %v KB",
    legend_labels_font_size = 12,
    outlabels_stretch = 15,
    show_legend = false
  }
  local i = 0
  for _,v in ipairs(top_cat) do
      table.insert(data.labels, v.name)
      table.insert(data.values, tonumber(string.format("%.2f", v.bytes/1024)) ) 
      table.insert(sugg, "who is in "..v.name)
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
  ntop_response.suggestions = sugg
  ntop_response.card = card

  return ntop_response
end

--#########################################################################################################

function handlers_module.who_is_categories(user_request)
  local category = user_request.queryResult.parameters.ndpi_category
  local tmp, res, sugg, byte_tot = {}, {}, {}, 0

  ----------------------------------------------------
  local function get_stats_callback(ip, stats)
    
    local h_stats = interface.getHostInfo(stats.ip)

    if h_stats["ndpi_categories"] and h_stats["ndpi_categories"][category] and h_stats["ndpi_categories"][category]["bytes"]then 
        table.insert(tmp, {
          bytes = h_stats["ndpi_categories"][category]["bytes"],
          name = getHostAltName( ip )
      })
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
      w = "500",
      h = "300",
      chart_type = "outlabeledPie",
      bkg_color = "white"
  }
  for i,v in ipairs(tmp) do
      if string.len(v.name) > label_max_len then 
        table.insert(data.labels,  string.sub(v.name,1,12) .. "..." )
      else 
        table.insert(data.labels,  v.name)
      end

      table.insert(sugg, v.name)
      table.insert(data.values, math.floor(( v.bytes / byte_tot ) * 100)  ) 
      if i >= limit_num_host_category_chart then break end    
  end

  local url = df_utils.create_chart_url(data, options)
  local image =  {img_url = url, img_description = "Top ".. category.." Local Hosts Chart" }
  local opt = { title = "Top ".. category.." Local Hosts Chart" }
  local card = dialogflow.create_card(nil, image, opt  )
  
  local display_text = "Here is the chart" 
  local speech_text =  "Here are the hosts that has generated most of the traffic for "..category

  ntop_response.speech_text = speech_text
  ntop_response.display_text = display_text
  ntop_response.suggestions = sugg    
  ntop_response.card = card

  return ntop_response
end

--#########################################################################################################

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
      byte_tot = byte_tot + host_stats["ndpi"][protocol]["bytes.sent"] + host_stats["ndpi"][protocol]["bytes.rcvd"] 
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
      w = "500",
      h = "300",
      chart_type = "outlabeledPie",
      bkg_color = "white"
  }
  for i,v in ipairs(tmp) do
    if string.len(v.name) > label_max_len then 
      table.insert(data.labels,  string.sub(v.name,1,12) .. "..." )
    else 
      table.insert(data.labels,  v.name)
    end

    table.insert(sugg, v.name)
    table.insert(data.values, math.floor(( v.bytes / byte_tot ) * 100)  ) 
    if i >= limit_num_host_protocol_chart  then break end    
  end

  local url = df_utils.create_chart_url(data, options)
  local image =  {img_url = url, img_description = "Top ".. protocol.." Local Hosts Chart" }
  local opt = { title = "Top ".. protocol.." Local Hosts Chart" }
  local card = dialogflow.create_card(nil, image, opt  )
  
  local speech_text = "Here is the chart"
  local display_text = " Here are the hosts that has generated most of the traffic for "..protocol

  ntop_response.speech_text = speech_text
  ntop_response.display_text = display_text
  ntop_response.suggestions = sugg    
  ntop_response.card = card

  return ntop_response
end

--#########################################################################################################

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
      h = "300",
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

    if table.len(sugg) > (limit_num_top_host-1) then break end  
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
    legend_labels_font_size = 12,
    outlabels_stretch = 17
  }
  local i = 1
  local status_txt = ""
  local max_score_flow = {score = 0}

  local score
  local flows_status_title_relevance_map = {}
  for i,v in pairs(flow_consts.status_types) do
    flows_status_title_relevance_map[v.status_id] = {title = v.i18n_title, relevance = v.relevance}
  end

  for status_id, v in pairs(mis_flows[1].status) do  
    status_txt = flows_status_title_relevance_map[status_id].title 

    status_txt = string.gsub(status_txt, "flow_details.", "") 
    status_txt = string.gsub(status_txt, "alerts_dashboard.", "[!] ") 
    status_txt = string.gsub(status_txt, "_", " ") 

    score = flows_status_title_relevance_map[status_id].relevance * v

    table.insert(data.datasets.data, score )
    table.insert(data.labels,  status_txt)

    if max_score_flow.score < score then 
      max_score_flow.id = status_id
      max_score_flow.score = score
      max_score_flow.descr = string.gsub(status_txt, "[!] ", "") 
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
  -- tprint(flow_consts.getStatusDescription(flow_id))
  -- tprint(flow_consts.getStatusTitle(flow_id))
  -- tprint(flow_consts.getStatusInfo(flow_id))

  --note: sync with host_info_more - security
  local speech_text, display_text, sugg, card = "", "", {}, {}
  local chart_description = "host misbehaving flow" --note: no title
  local data = {labels = {}, datasets = { data = {} }}
  local options = { 
    w = "500",
    h = "300",
    chart_type = "outlabeledPie", 
    bkg_color = "white",
    outlabels_text = "ThreatScore: %v ",
    legend_labels_font_size = 12,
    outlabels_stretch = 15
  }
  local card_opt, card_text = nil, nil --for weblink --> JA3 in malicious_signature
  local score = flow_consts.getStatusInfo(flow_id).relevance * host_mis_flows.status[flow_id]
  local flow_title = flow_consts.getStatusTitle(flow_id)
  local flow_description = flow_consts.getStatusDescription(flow_id) 

  if not flow_title then 
  --case: no id match 
    ntop_response.speech_text = "Ops, there is a problem with the flow status, try later!"
    return ntop_response 
  end

  local num_tot_flows = 0
  for i,v in pairs(host_mis_flows.status) do
    num_tot_flows = num_tot_flows +  v
  end

  --case: standard management
  display_text = "The host "..
  ternary(getHostAltName(host_ip) ~= host_ip," named ".. getHostAltName(host_ip)..",", "" )..
  " has generated ".. host_mis_flows.status[flow_id].. " '"..flow_title.."' out of "..num_tot_flows

  speech_text =  "The host has generated ".. host_mis_flows.status[flow_id].. " '"..flow_title.."' out of "..num_tot_flows..
                "\nDescription: "..flow_description

  local status_txt = "" --note: for compatibility with the dialogflow enity
  for status_id, v in pairs(host_mis_flows.status) do  
    status_txt = flow_consts.getStatusInfo(flow_id).i18n_title
    status_txt = string.gsub(status_txt, "flow_details.", "") 
    status_txt = string.gsub(status_txt, "alerts_dashboard.", "[!] ") 
    status_txt = string.gsub(status_txt, "_", " ") 
    table.insert(data.datasets.data, score )
    table.insert(data.labels, status_txt)

    if table.len(labels) == limit_num_top_host then break end
  end  
  sugg = table.merge(  data.labels, {"more applications", "more categories", "more security" } )

  --case: particular management due to the "IF-CSD 2019"
  if flow_id == 27 --[[status_malicious_signature]] then    

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
  
    --note: num max label = 12
    sugg = table.merge(  data.labels, {"more applications", "more categories", "more security" } )
    local url = "https://sslbl.abuse.ch/ja3-fingerprints/"..ja3
    card_opt = { weblink_title = "JA3", weblink = url}  --no title?
    card_text = "SSL blacklist, by abuse:"
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

--TODO: in categories and applications chart, makae the "other" group: put there the proto/cat with low %
function handlers_module.host_info_more(user_request)
  local info_type = user_request.queryResult.parameters.host_info--note: info type = general - applications - security - categories - network
  local ip = ntop.getCache("nAssistant_host_info_ip")

  local host_info = interface.getHostInfo(ip)
  local is_chart = false
  local speech_text, display_text

  local sugg = {"more applications", "more categories", "more network", "more security", "more host info" }

  if not host_info then 
    ntop_response.speech_text = "Can't find the host address! Please ask me something else" 
    return ntop_response
  end

  if not host_info.name or host_info.name == "" then host_info.name = getHostAltName( host_info.ip) end
  if not host_info.name or host_info.name == "" then host_info.name = host_info.ip end

  local labels, values, datasets = {},{},{}
  local legend_label = "Traffic (KB)"
  local data = {labels = {}, values = {}, legend_label = legend_label}
  local options = { 
    w = "550",
    h = "300",
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

    if not host_mis_flows then 
      ntop_response.speech_text = "No misbehaving flows detected"
      ntop_response.display_text = "No misbehaving flows detected"
      ntop_response.suggestions = sugg    
      return ntop_response
    end

    options = { 
      w = "500",
      h = "300",
      chart_type = "outlabeledPie", 
      bkg_color = "white",
      outlabels_text = "ThreatScore: %v ",
      legend_labels_font_size = 12,
      outlabels_stretch = 17
    }
    is_chart = true
    chart_description = "Security for ".. host_info.name 
    card_title = "Security for ".. host_info.name 
    local status_txt = ""
    local max_score_flow = {score = 0}
    local score
    local flow_consts = require "flow_consts"
    local flows_status_title_relevance_map = {}
    for i,v in pairs(flow_consts.status_types) do
      flows_status_title_relevance_map[v.status_id] = {title = v.i18n_title, relevance = v.relevance}
    end

    for status_id, v in pairs(host_mis_flows.status) do  
      status_txt = flows_status_title_relevance_map[status_id].title  
  
      status_txt = string.gsub(status_txt, "flow_details.", "") 
      status_txt = string.gsub(status_txt, "alerts_dashboard.", "[!] ") 
      status_txt = string.gsub(status_txt, "_", " ") 
      score = flows_status_title_relevance_map[status_id].relevance * v
      table.insert(data.values, score )
      table.insert(data.labels,  status_txt)
  
      if max_score_flow.score < score then 
        max_score_flow.id = status_id
        max_score_flow.score = score
        max_score_flow.descr = string.gsub(status_txt, "[!] ", "") --TODO: fix!!! "[!]" not removed
      end
  
      if table.len(labels) == limit_num_top_host then break end
    end
    sugg = table.merge(data.labels, {"more applications", "more categories", "more network" })

    display_text = getHostAltName( host_mis_flows.addr)
    if getHostAltName( host_mis_flows.addr) ~= host_mis_flows.addr then 
      display_text = display_text .. "  (".. host_mis_flows.addr..")"
    end
  
    ntop.setCache("nAssistant_misbehaving_host_ip", host_mis_flows.addr, 60*20 )
  
    speech_text = "The host has generated ".. host_mis_flows.flow_counter.." suspected flow in total."..
                  "The most dangerous seems to be: \""..max_score_flow.descr.."\" with a score of ".. max_score_flow.score..
                  " based on ".. host_mis_flows.status[max_score_flow.id].. " flows of that type."

  elseif info_type == "network" then ------------------------------------

    --TODO: goodput, tcpPktStats per l'efficienza, ecc... vedi tabella a fondo pagina
    display_text = "Interface Name = "..ifname.."\nAddresses:\nIP = "..host_info.ip.."\n"..
          ternary(host_info.mac , "MAC = "..host_info.mac.."\n" , "" )

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

--#########################################################################################################

function handlers_module.host_info(user_request)
  local text = "I don't get it, can you repeat please?"
  local host_name = user_request.queryResult.queryText
  if (not host_name) or (host_name == "") then
    ntop_response.speech_text =  text 
    return ntop_response
  end

  --first try: name match
  local host_info, sugg = interface.getHostInfo(host_name), {}

  --second try: alternative name match
  if not host_info then
    host_info = interface.getHostInfo( getHostAltName(host_name) )
  end

  --third try: partial name
  if not host_info then
    local addrs = interface.findHost(host_name) --findHost BUG! non sempre è capace di trovare il nome partendo da una parte di esso, inoltre col "-" si rompe (esempio: ANGKOK-8AC2-PC dal pcap di esercizio)

    if table.len(addrs) == 1 then -- 1 match
      for k,v in pairs(addrs) do
         host_info = interface.getHostInfo( k )
         break
      end
    end
    if table.len(addrs) > 1 then --many match
      for k,v in pairs(addrs) do
        table.insert(sugg, getHostAltName(k))
      end
      ntop_response.speech_text = "I found this, please select one of the suggestions"
      ntop_response.suggestions = sugg 

      return ntop_response
    end
  end

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

  if mac_info and mac_info.manufacturer then 
    text = text ..ternary(mac_info.manufacturer , "Manufacturer "..mac_info.manufacturer.."\n" , "" )
        --  ..ternary(mac_info.model, "Model "..mac_info.model.."\n" , "" )
  end

  ntop_response.speech_text = "Here you have some info about the host"
  ntop_response.display_text = text
  ntop_response.suggestions = sugg    

  return ntop_response
end

return handlers_module
