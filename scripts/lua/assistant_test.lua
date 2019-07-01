--
-- (C) 2019 - ntop.org
--

dirs = ntop.getDirs()
package.path = dirs.installdir .. "/scripts/lua/?.lua;" .. package.path
if((dirs.scriptdir ~= nil) and (dirs.scriptdir ~= "")) then package.path = dirs.scriptdir .. "/lua/modules/?.lua;" .. package.path end
ignore_post_payload_parse = 1
require "lua_utils"

local google = require "google_assistant_utils"
local net_state = require "network_state"

local response, request

--NOTE: la parte di telegram è decisamente provvisoria, studia il modo per usare il bot senza fare hard-code del chat bot / id


--[[
see "ndpi_get_proto_breed_name( ... )" in ndpi_main.c for more info

NDPI_PROTOCOL_SAFE:                   "Safe"           /* Surely doesn't provide risks for the network. (e.g., a news site) */
NDPI_PROTOCOL_ACCEPTABLE:             "Acceptable"     /* Probably doesn't provide risks, but could be malicious (e.g., Dropbox) */
NDPI_PROTOCOL_FUN:                    "Fun"            /* Pure fun protocol, which may be prohibited by the user policy (e.g., Netflix) */
NDPI_PROTOCOL_UNSAFE:                 "Unsafe"         /* Probably provides risks, but could be a normal traffic. Unencrypted protocols with clear pass should be here (e.g., telnet) */
NDPI_PROTOCOL_POTENTIALLY_DANGEROUS:  "Dangerous"      /* Surely is dangerous (ex. Tor). Be prepared to troubles */
NDPI_PROTOCOL_UNRATED:                "Unrated"        /* No idea, not implemented or impossible to classify */
]]--

---------------------------------UTILITY FUNCTIONS------------------------------------------

local function translate_ndpi_breeds(table)
  local t = {}

  for i,v in pairs(table) do
    if        i == "Safe"         then t["Sicuro"] = v
    elseif    i == "Unsafe"       then t["Potenzialmente Pericoloso"] = v
    elseif    i == "Dangerous"    then t["Pericoloso"] = v
    elseif    i == "Fun"          then t["Divertimento"] = v
    elseif    i == "Acceptable"   then t["Accettabile"] = v
    else      t["Altro"] = v
    end
  end
  
  return t
end

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
  if score >= 99 then 
    safe_text = ", in generale, sono sicure"
  elseif score >= 90 then
    safe_text = "sono per la maggior parte sicure"
  elseif score >= 75 then
    safe_text = "sono per lo più sicure"
  elseif score >= 50 then
    safe_text = "sono parzialmente sicure"
  elseif score >= 25 then
    safe_text = "sono poco sicure"
  else 
    safe_text = "sono potenzialmente pericolose"
  end

  local bl_num_txt = ""
  if blacklisted_host_num == 0 then
    bl_num_txt = "Nessun host indesiderato.\n"
  elseif blacklisted_host_num == 1 then
    bl_num_txt = "Un host indesiderato.\n"
  else 
    bl_num_txt = blacklisted_host_num .. " host indesiderati.\n"
  end

  text = bl_num_txt .. "Le comunicazioni "..safe_text

  if danger then text = text .. ". \nMa attenzione! È stato rilevato traffico pericoloso! " end

  return text
end


local function send_text_telegram(text) 
  local chat_id, bot_token = ntop.getCache("ntopng.prefs.telegram_chat_id"), ntop.getCache("ntopng.prefs.telegram_bot_token")

  io.write(chat_id.." "..bot_token )

    if( string.len(text) >= 4096 ) then 
      text = string.sub( text, 1, 4096 )
    end

    if (bot_token and chat_id) and (bot_token ~= "") and (chat_id ~= "") then 
      os.execute("curl -X POST  https://api.telegram.org/bot"..bot_token.."/sendMessage -d chat_id="..chat_id.." -d text=\" " ..text.." \" ")
      return 0

    else
      return 1
    end
end

local function danger_app()
  local danger_apps = net_state.check_dangerous_traffic()
  local text = "Ho rilevato queste applicazioni pericolose:\n"
  local unit = "bytes"

  local display_text = "Applicazioni pericolose:\n"
  local display_unit = unit

  if danger_apps == nil then 
    text = "Non rilevo nessuna comunicazione pericolosa"
    display_text = "Non rilevo nessuna comunicazione pericolosa"
    return text, display_text, false

  else
    for i,v in pairs(danger_apps) do
      tb = v.total_bytes 

      if tb > 512 then 
        tb = math.floor( (tb / 1024) * 100 )/100
        unit = "KiloBytes"
        display_unit = "KB"
      end
      if tb > 512 then
        tb = math.floor( (tb / 1024) * 100 )/100
        unit = "MegaBytes"
        display_unit = "MB"
      end

      text = text.. v.name .. " che ha generato un volume di traffico pari a " ..tb .. " "..unit.."\n"
      display_text = display_text .."-" ..v.name .. ". volume traffico: "..tb.." ".. display_unit .."\n" 
    end
  end

  return text, display_text, true
end

-------------------------------------INTENTS HANDLER FUNCTIONS-------------------------------------------


local function handler_upTime()
  local uptime, time = secondsToTime( ntop.getUpTime() )
  if uptime > 3600 then
    time = secondsToTime( uptime ) 
  else
    time = math.floor(uptime / 60).." minuti e ".. math.fmod(uptime, 60).. " secondi"
  end

  google.send( "Sono in esecuzione da ".. time  ) 
end


local function handler_Network_State()
  local stats = net_state.check_ifstats_table()
  local alert_num, severity = net_state.check_num_alerts_and_severity()
  local alert_text = ""

  if alert_num > 0 then
    alert_text = alert_num .. " allarmi scattati, di cui "

    for i,v in pairs(severity) do
      if v > 0 then  alert_text = alert_text .. v .. " " .. i .. ", " end
    end

    alert_text = string.sub(alert_text,1,-2)
    alert_text = string.sub(alert_text,1,-2)
    alert_text = alert_text..".\n"

  else
    alert_text = "0 allarmi scattati\n"
  end

  local app_host_good_text, b, danger = are_app_and_hosts_good() --TODO: "b" a che serve? rimuovila in caso

  local text = "Rilevo:\n"..stats.device_num.." dispositivi collegati, "..stats.local_host_num..
  " host locali, "  ..stats.flow_num.." flussi attivi.\n".. alert_text.. app_host_good_text

  local sugg = {}
  if danger and alert_num > 0 then 
    sugg = {"traffico pericoloso", "allarmi attivi"}
  elseif danger and alert_num == 0  then
    sugg = {"traffico pericoloso"}
  elseif not danger and alert_num > 0   then
    sugg = {"allarmi attivi"}
  else --not danger and alert_num == 0
    sugg = {}
  end

  google.send(text, nil, nil, sugg)
end


local function handler_network_state_communication()
  local stats, text = net_state.check_net_communication(),""
  local ctg, prc = net_state.check_top_traffic_application_protocol_categories()

  if stats.prc_remote2local_traffic + stats.prc_local2remote_traffic < 50 then
    text = text .. "Il traffico è prevalentemente interno alla rete "
  elseif stats.prc_remote2local_traffic > stats.prc_local2remote_traffic then 
    text = text .. "La maggior parte del traffico dati proviene dall'esterno della rete, "
  else 
    text = text .. "Il traffico è per lo più inviato verso l'esterno della rete, "
  end

  text = text .. " di cui il "..prc.." percento è di tipo "..ctg..

  ". L'efficienza di trasmissione dati è "..net_state.check_TCP_flow_goodput() ..". Dimmi pure se vuoi approfondire qualcosa"

  google.send( text, nil, nil, {"categorie traffico","efficienza trasmissioni","traffico locale/remoto"} )
end


local function handler_traffic_app_info()
  local stats = net_state.check_top_application_protocol()
  local text, top_num, j = "", 0, 1
  
  if      stats[3] then top_num = 3
  elseif  stats[2] then top_num = 2
  elseif  stats[1] then top_num = 1
  end

  if top_num == 1 then 
    text = "L'unico protocollo applicativo rilevato è "..stats[1][1].." con il "..stats[1][2] .." percento del traffico."
  end

  local text_name, text_perc
  if top_num > 1 then 
    text_name = "I ".. top_num .." principali protocolli applicativi sono: "..(stats[1][1] or "")..", "..(stats[2][1] or "")..", e "..(stats[3][1] or "")
    text_perc = "; Con un traffico, rispettivamente, del "..(stats[1][2] or "")..", "..(stats[2][2] or "")..", "..(stats[3][2] or "").. " percento"
    text = text_name..text_perc
  else 
    text = "Non ho ancora rilevato nessun protocollo applicativo" 
    google.send(text)
  end


  local display_text = ""
  for i=1,3 do
    if stats[i] then 
      display_text = display_text .. stats[i][1]..": ".. stats[i][2].."%;\n"
    end
  end


  if #stats > 5 then
    text = text .. ". Vuoi che ti scriva l'elenco delle ".. #stats-top_num.." app rimanenti?"
    display_text = display_text .. "Vuoi che ti scriva l'elenco delle ".. #stats-top_num.." app rimanenti?"
  end

  google.send(text, display_text, nil, {"Sì","No"})
end

local function handler_traffic_app_info_more_info()
  local stats, text = net_state.check_top_application_protocol(), ""
  local if_0 = "< 1%; "

  for i,v in pairs(stats) do
    if i > 3 then
      if v[2] == 0 then 
        text = text ..  v[1]..": "..if_0
      else
        text = text ..  v[1]..": "..v[2].." %; "
      end
      text = text .. "\n"
    end
  end

  google.send("Ecco a te l'elenco",text)
end


local function handler_device_info()
  local info, devices_num = net_state.check_devices_type()
  local text2 = ""
  
  text = "Rilevo "..  devices_num.. " dispositivi collegati. "

  for i,v in pairs(info) do
    if i ~= "Unknown" then text2 = text2 .. v.. " ".. i.. ", " end
  end

  if text2 ~= "" then 
    text =  text .. "Tra cui ".. text2
  end

  text = text .. ". Vuoi informazioni più dettagliate? Altrimenti dimmi il nome, o l'indirizzo, di un dispositivo"

  google.send(text, text, true, {"Sì","No"})
end

--TODO: pagination for devices info, or
--      redesign the dialog (use the device info fallback intent to retreive the addr/name of device)
local function handler_send_devices_info()
  local limit, text = request["parameters"]["number"], ""
  local discover = require "discover_utils"
  local callback = require "callback_utils"
  local devices_stats = callback.getDevicesIterator()
  local manufacturer = ""

  local cont = 0
  for i, v in devices_stats do

    if v.source_mac and (cont < limit) then 
      cont = cont + 1
      text = text .. cont .." Nome: ".. getHostAltName(v.mac) .. "\n"
      if v.manufacturer then manufacturer = v.manufacturer else manufacturer = "Sconosciuto" end
      text = text .. "Costruttore: " .. manufacturer .. "\n"
      text = text .. "Mac: " .. v.mac .. "\n"
      text = text .. "Tipo: " .. discover.devtype2string(v.devtype) .. "\n"
      text = text .. "Byte inviati " .. v["bytes.sent"] .. "\n"
      text = text .. "Byte ricevuti " .. v["bytes.rcvd"] .. "\n"
      text = text .. "\n"
    end
    
  end

  if limit > 4 then  
    if (send_text_telegram(text) == 0) then
      google.send("Info inviate su Telegram")
    else
      google.send("Ops, invio su Telegram fallito. Sicuro di aver impostato token e chat id?")
    end
  else
    google.send("Ecco a te", text)
  end

end


local function handler_suspicious_activity_more_info()
  local ndpi_breeds, blacklisted_host_num, danger = net_state.check_bad_hosts_and_app()
  local res = {}
  local text = ""
  local d_text = ""
  local alert_text = ""

  d_text = "Traffico dati:\n"
  text = d_text

  if  ndpi_breeds["Safe"] then
    table.insert( res, {nome = "è sicuro", perc = ndpi_breeds["Safe"]["perc"], bytes = ndpi_breeds["Safe"]["bytes"]  } )
  end

  if  ndpi_breeds["Acceptable"] and ndpi_breeds["Fun"]  then
    table.insert( res, {nome = "è accettabile", perc = ndpi_breeds["Acceptable"]["perc"]  + ndpi_breeds["Fun"]["perc"], bytes = ndpi_breeds["Acceptable"]["bytes"] + ndpi_breeds["Fun"]["bytes"] } )
    
  elseif  ndpi_breeds["Acceptable"]   then
    table.insert( res, {nome = "è accettabile", perc = ndpi_breeds["Acceptable"]["perc"], bytes = ndpi_breeds["Acceptable"]["bytes"] } )
  end
  
  if  ndpi_breeds["Unrated"] then
    table.insert( res, {nome = "non è valutabile", perc = ndpi_breeds["Unrated"]["perc"], bytes = ndpi_breeds["Unrated"]["bytes"] } )
  end

  if  ndpi_breeds["Other"] then
    table.insert( res, {nome = "è di altro tipo", perc = ndpi_breeds["Other"]["perc"], bytes = ndpi_breeds["Other"]["bytes"] } )
  end

  if  ndpi_breeds["Dangerous"] then
    table.insert( res, {nome = "è pericoloso", perc = ndpi_breeds["Dangerous"]["perc"], bytes = ndpi_breeds["Dangerous"]["bytes"] } )
  end

  local function compare(a, b) return a["perc"] > b["perc"] end
  table.sort(res, compare)

  local if_0 = "< 1%"

  for i,v in pairs(res) do 
    if v and v.perc == 0 and  v.bytes > 0 then 
      text = text .. "meno dell' 1 percento del traffico "..v.nome..","
    elseif v and v.bytes and v.bytes > 0 then
      text = text.." il "..v.perc.." percento del traffico "..v.nome..","
    end
  end

  
  for i,v in pairs(res) do 
    if v.perc == 0 and v.bytes and v.bytes > 0 then 
      d_text = d_text .. if_0 .. " ".. v.nome..";\n"
    elseif v and v.bytes and v.bytes > 0 then
      d_text = d_text.. v.perc .. "% "..v.nome..";\n"
    end
  end

  danger_text, danger_display_text, danger_flag = danger_app()
  if danger_flag then

    text = text .."\n\n"..danger_text
    d_text = d_text .."\n\n" .. danger_display_text

  end

  google.send(text, d_text)
end


local function handler_suspicious_activity()

  google.send( are_app_and_hosts_good() ..  ". Vuoi saperne di più sulla sicurezza del traffico?", nil, nil, {"Sì", "No"} )
end


local function local_remote_traffic()
  local stats, text = net_state.check_net_communication(),""

  text = "il "..stats.prc_remote2local_traffic.."% del traffico è in entrata, il "..
  stats.prc_local2remote_traffic.." è in uscita e il "..100 -(stats.prc_remote2local_traffic +stats.prc_local2remote_traffic)  .."% è interno alla rete. "

  return text
end

local function flow_efficency()
  local global_state, flow_tot, bad_gp = net_state.check_TCP_flow_goodput()
  local stats= net_state.check_net_communication()

  local text = "l'efficienza delle comunicazioni è " .. global_state .. ". Su ".. flow_tot .. " flussi attivi "..bad_gp.. " hanno rallentamenti. "

  if stats.prc_pkt_drop < 1 then text = text .. "La perdita di pacchetti è trascurabile"
  else text =  text .. "Sono andati persi il".. stats.prc_pkt_drop .. "% pacchetti."
  end

  local display_text = "l'efficienza delle comunicazioni è " .. global_state .. ". Su ".. flow_tot .. " flussi (TCP) attivi "..bad_gp.. " hanno rallentamenti. "

  local pkt_drop_txt= ""
  if stats.prc_pkt_drop == 0.000 then pkt_drop_txt = "< 0.01%"
  else pkt_drop_txt = pkt_drop_txt .. stats.prc_pkt_drop .. "%"
  end

  if stats.prc_pkt_drop < 0.09 then display_text = display_text .. "La perdita di pacchetti è trascurabile: "..pkt_drop_txt.."\n"
  else 
    display_text =  display_text .. "Persi il ".. stats.prc_pkt_drop .. "% pacchetti.\n"
  end
  display_text = display_text.. "[ " .. stats.num_pkt_drop.. " su " .. stats.num_tot_pkt.."]"

  return text, display_text
end


local function handler_traffic_category()
  local categories = net_state.check_traffic_categories()
  local text, d_text = "", ""

  local cont = 0
  
  for i,v in pairs(categories) do
    if v.perc > 10 then cont = cont + 1 end
  end

  if cont == 0 then 
    text = "non riesco a rilevare le categorie del traffico"
    return google.send(text)

  elseif cont == 1 then 
    text = "L'unica categoria rilevante è ".. categories[1].name.. " con il "..categories[1].perc.."% del traffico"

  else
    text = "Le "..cont.."categorie più rilevanti sono: "
    for i,v in pairs(categories) do
      if v.perc > 10 then 
        text = text .. categories[i].name .. " con il ".. categories[i].perc.."%;\n"
      end
    end
  end

  for i,v in pairs(categories) do
    d_text = d_text .. categories[i].name .. " - ".. categories[i].perc.."%;\n"
  end

  return text, d_text
end

--TODO: rivedi, era stato pensato per accumulare info, ma in realtà non lo sta facendo! prende un solo parametro e non itera sugli altri
local function handler_network_state_communication_more_info() 
  local param, text, display_text = request["parameters"]["Communication"], "Ops, ho un problema, prova a chiedermi altro", "Ops, ho un problema, prova a chiedermi altro"
  local v = param[1]

  if     v == "categorie traffico"      then 
    text, display_text =  handler_traffic_category()

  elseif v == "traffico locale/remoto"  then 
    text = local_remote_traffic()
    display_text = text
  elseif v == "efficienza trasmissioni" then 
    text, display_text =  flow_efficency()

    for ii,vv in pairs(param) do
      if v == vv then table.remove( param, ii ) end 
    end

  end

  google.send(text, display_text, nil, {"categorie traffico","traffico locale/remoto","efficienza trasmissioni"})
end


local function handler_dangerous_communications_detected()

  local text, display_text = danger_app()
  google.send(text, display_text)
end


local function handler_ntopng()
  local display_text = "Sono l'assistente vocale di ntopng"
  local speech_text = "Sono l'assistente vocale di n top n g, scopri di più visitando il sito!"
  local card_title = "ntopng: High-Speed Web-based Traffic Analysis and Flow Collection"
  local card_url_image = "https://www.ntop.org/wp-content/uploads/2011/08/ntopng-icon-150x150.png"
  local accessibility_text = "ntopng_logo"
  local button_title = "Vai al sito"
  local button_open_url_action = "https://www.ntop.org/products/traffic-analysis/ntop/"
  local card = google.create_card(card_title, card_url_image, accessibility_text,button_title, button_open_url_action)

  google.send(speech_text, display_text, nil, nil, card)
end


local function handler_what_can_you_do()
  local text = "Posso tenerti aggiornato sullo stato della tua rete, descriverti come vanno le comunicazioni, dirti chi è connesso in questo momento, informarti se ci sono attività sospette in corso, avviare una cattura di pacchetti e molto altro!"
  sugg = {
    "Come sta la rete",
    "Stato delle comunicazioni",
    "Traffico Applicativo",
    "Attività sospette",
    "Dispositivi connessi",
    "Avvia cattura pacchetti",
    "Chi sei",
    "Tempo dall'avvio"
  }

  google.send(text, nil, nil, sugg)
end


local function handler_alert_more_info()
  local text, display_text = "",""
  local alerts = net_state.alerts_details()

  if not alerts then 
    google.send("Non ci sono allarmi da segnalare")
    return
  end

  display_text = "Allarmi scattati:\n\n"

  for i,v in pairs(alerts) do

    for ii,vv in pairs(v) do
      display_text = display_text .. ii .. ": " .. vv .. "\n"
    end

    display_text = display_text .. "\n"
  end
  text = "Ecco a te l'elenco degli allarmi scattati:\n"

  if #alerts > 2 then 
    if (send_text_telegram(display_text) == 0) then
      google.send("Ti ho inviato le informazioni su Telegram")
    else
      google.send("Ops, invio su Telegram fallito. Sicuro di aver impostato token e chat id?")
    end

  else
    google.send(text, display_text)
  end
end

local function handler_alert()
  local alert_num, severity = net_state.check_num_alerts_and_severity()
  local alert_text = ""

  if alert_num > 0 then
    alert_text = alert_num .. " allarmi scattati, di cui "

    for i,v in pairs(severity) do
      if v > 0 then  alert_text = alert_text .. v .. " " .. i .. ", " end
    end

    alert_text = string.sub(alert_text,1,-2)
    alert_text = string.sub(alert_text,1,-2)
    alert_text = alert_text..". Vuoi più dettagli riguardo gli allarmi?"

    google.send(alert_text, alert_text, nil, { "Sì", "No"})
  else
    alert_text = "0 allarmi scattati\n"
    google.setContext(request["context"], 0, nil)
    google.send(alert_text, alert_text)
  end
end


local function handler_tcp_dump()
  local duration_amount, duration_unit = request.parameters.duration.amount, request.parameters.duration.unit
  --possible values of "unit": s - min - h - day

  local seconds = 10
  local unit_text

  if      duration_unit == "s"    then 
    seconds = duration_amount 
    unit_text = "secondi"

  elseif  duration_unit == "min"  then 
    seconds = duration_amount * 60
    unit_text = "minuti"
    
  elseif  duration_unit == "h"    then 
    seconds = duration_amount * 60 * 60
    unit_text = "ore"

  elseif  duration_unit == "day"    then 
    seconds = duration_amount * 60 * 60 * 24
    unit_text = "giorni"
  end

  local text = "OK! Catturerò i pacchetti per ".. duration_amount.. " ".. unit_text
  local path = interface.captureToPcap(seconds )

  if path then
     io.write("\n"..os.date("%c")..": the pcap file is here: "..path.."\n") 
     ntop.setPref("ntopng.prefs.dump_file_path", path)

    if(interface.isCaptureRunning()) then
      ntop.msleep(1000)
    end
    
    interface.stopRunningCapture()
    --io.write("\n"..os.date("%c")..": pcap file: "..path.." capture finished".."\n") 
  
    text = text .. "\n\nQuando vorrai, per ricevere il file di cattura su Telegram ti basterà dire 'inviami il file su Telegram' "
    google.send(text)

  else 
    io.write("\nerror: pcap file not created\n")

    google.send("Mi dispiace, ma non riesco a lanciare la cattura!")
  end
end


local function handler_send_dump()
  local chat_id, bot_token = ntop.getCache("ntopng.prefs.telegram_chat_id"), ntop.getCache("ntopng.prefs.telegram_bot_token")
  io.write("token & id:"..bot_token .." - " .. chat_id )

  local file_path = ntop.getPref("ntopng.prefs.dump_file_path")

  if file_path then 

    if interface.isCaptureRunning() then
       interface.stopRunningCapture() 
       io.write("\n"..os.date("%c")..": pcap file: "..path.." capture stopped".."\n") 
    end

    if (bot_token and chat_id) and (bot_token ~= "") and (chat_id ~= "") then 
      os.execute("curl -F chat_id="..chat_id.." -F document=@"..file_path.." https://api.telegram.org/bot"..bot_token.."/sendDocument ")
      google.send("File inviato!")
    else
      google.send("Ops, invio su Telegram fallito. Sicuro di aver impostato token e chat id?")
    end

  else
    google.send("Ops, non ho trovato il file. Sei sicuro di aver avviato la cattura?")
  end
end


--WIP
--IDEA: rich message response con link per i nomi delle appliczioni di sistema (es. MDNS)

--NOTE: dovrei ignorare il traffico MDNS? o traffico di altri protocolli di rete simili (forse tutto ciò che ha breed = Network?)

--TODO: controlla se: è addr/nome? se si allora mi da le info dettagliate su quel dispositivo
local function handler_device_info_fallback() --è una "finta fallback"
  local queryText = request.queryText
  local text = ""
  local info = interface.findHost(queryText)
  local total_bytes = 0
  local mac = nil
  local dev_type = "Sconosciuto"
  local name = ""
  local ndpi_table = {}
  local ndpi_categories_table = {}
  local name = "Sconosciuto"
  local tmp = {}

  --local os = "Sconosciuto"
  local host_pool = nil
  local goodput = nil
  local num_alerts = 0

  --controllo parametro
  if queryText:find(" ") then -- + di una parola, non è un nome/indirizzo
    google.send("Scusa ma non ho capitpo il nome del Dispositivo, puoi ripetere?")
    return --todo: suggerimenti + testo che invita ad usare i suggerimenti o come fare la richiesta
  end

  --ricerca mac/tabella info mac
  for i,v in pairs(info) do
    local host_info = interface.getHostInfo(i)

    if host_info then
      mac_info = interface.getMacInfo( host_info.mac )
    end

    if mac_info then break end
  end


  if mac_info then 
    local ndpi_categories = net_state.check_ndpi_categories()

    if mac_info.devtype then 
      local discover = require "discover_utils" 
      dev_type = discover.devtype2string( mac_info.devtype )
    end

    if ndpi_categories then --ndpi_categories
      text = text .. "\nCategorie Traffico:\n"
      --note: in "mac_info" the sum of the ndpi_category.byte(rcvd/snt) =\= tot_byte(rcvd/snt). idk_y 
      for _,b in pairs(ndpi_categories) do 
        total_bytes = total_bytes + b
      end

      --TODO: se non uso la "ndpi_categories_table" accorpa i cicli e fai subito la tabella come array per la sort
      for i,v in pairs(ndpi_categories) do
        ndpi_categories_table[i] = math.floor( (v / total_bytes) * 100 )
      end

      --creo array e ordino
      for i,v in pairs(ndpi_categories_table) do table.insert(tmp, {name=i,perc=v} ) end
      table.sort(tmp, function (a,b) return a["perc"] > b["perc"] end)

      --stampo solo se perc>1, max 5 categorie
      local c = 1
      for _,v in pairs(tmp) do
        if v.perc > 1 and c < 5 then --5 è un limite temporaneo
          text = text .."- ".. v.name .. ": "..v.perc.."%\n" 
        end
        c = c + 1
      end

    end--END categories info

    total_bytes = 0

    
    --note: cos'è "childSafe boolean false" ?
    --NOTE: ciclo perché potrebbero esserci più host per tale devices
    for addr,v in pairs(info) do --ndpi
      
      local host_info = interface.getHostInfo(addr)

      if host_info then 
        --tprint(host_info)

        if host_info.name then 
          if name and ( name:len() > host_info.name:len() ) then 
          name = host_info.name
          end
        end

        if host_info.ndpi then 

          for _,b in pairs(host_info.ndpi) do 
            total_bytes = total_bytes + b["bytes.sent"] + b["bytes.rcvd"]
          end

          for ii, vv in pairs(host_info.ndpi) do
            --local prc = math.floor( ( (vv["bytes.sent"] + vv["bytes.rcvd"]) / total_bytes ) * 100 )
            ndpi_table[ii] = (ndpi_table[ii] or 0) + vv["bytes.sent"] + vv["bytes.rcvd"]
          end
        end--END ndpi

        io.write("end host -----------------------------------------------------------------------------")
      end--END host_info
    end--END for-host_info

    tmp = {}
    for i,v in pairs(ndpi_table) do table.insert(tmp, {name=i,perc=v} ) end
    table.sort(tmp, function (a,b) return a["perc"] > b["perc"] end)

    text = text .. "\nApplicazioni:\n"

    --stampo solo se perc>1, max 5 app
    local c = 1
    for _,v in pairs(tmp) do
      local perc = math.floor( (v.perc / total_bytes) * 100 )
      if perc > 1 and c < 5 then --5 è un limite temporaneo
        text = text .."- ".. v.name .. ": "..perc.."%\n" 
      end
      c = c + 1
    end

  end

  --metto nome e tipo in cima
  text = name .. " - "..dev_type .. "\n"..text
  google.send(text)  
end


--[[
  MAC INFO EXAMPLE

    idea: "num_hosts:1" può essere il discriminante per poi fare il "interface.findHost(...)",
    prendere i dati degli host e BAM, così posso esporre anche altro (tipo le applicazioni, ecc.)

  {
  "seen.last":1561537296,
  "special_mac":false,
  "throughput_bps":71.983856201172,
  "location":"lan",
  "arp_replies.rcvd":0,
  "bytes.rcvd.anomaly_index":0,
  "bytes.ndpi.unknown":0,
  "packets.sent":112162,
  "bytes.sent.anomaly_index":75,
  "bytes.sent":6729720,
  "last_throughput_bps":71.98420715332,
  "bytes.rcvd":0,
  "throughput_trend_bps_diff":-0.0003509521484375,
  "num_hosts":1,
  "arp_requests.sent":0,
  "manufacturer":"ICANN, IANA Department",
  "mac":"00:00:5E:00:01:61",
  "fingerprint":"",
  "packets.rcvd.anomaly_index":0,
  "ndpi_categories":{
    "Network":{
      "category":14,
      "bytes.sent":6699270,
      "bytes":6700290,
      "duration":97780,
      "bytes.rcvd":1020
    },
    "Unspecified":{
      "category":0,
      "bytes.sent":654,
      "bytes":1404,
      "duration":5,
      "bytes.rcvd":750
    }
  },
  "source_mac":true,
  "devtype":3,
  "seen.first":1560506203,
  "duration":1031094,
  "arp_replies.sent":0,
  "throughput_trend_pps":2,
  "pool":0,
  "ndpi":[],
  "operatingSystem":0,
  "packets.sent.anomaly_index":100,
  "throughput_trend_bps":2,
  "packets.rcvd":0,
  "bridge_seen_iface_id":1,
  "throughput_pps":1.1997309923172,
  "last_throughput_pps":1.1997367143631,
  "arp_requests.rcvd":0
}


HOST INFO
table
seen.first number 1560506203
throughput_trend_bps_diff number 0.0
devtype number 3
bytes.sent.anomaly_index number 67
udpBytesSent.unicast number 0
active_flows.as_client number 1
icmp.bytes.rcvd number 0
systemhost boolean false
unreachable_flows.as_server number 0
flows.as_server number 507
throughput_trend_pps number 3
name string toprak
icmp.bytes.sent.anomaly_index number 0
udp.packets.sent number 572
bytes.ndpi.unknown number 55708
throughput_bps number 0.0
total_alerts number 468
other_ip.packets.sent number 0
packets.sent.anomaly_index number 0
local_network_name string 146.48.96.0/22
local_network_id number 2
ssl_fingerprint table
longitude number 12.109700202942
pktStats.sent table
pktStats.sent.upTo256 number 254
pktStats.sent.upTo1518 number 76
pktStats.sent.upTo128 number 186
pktStats.sent.finack number 0
pktStats.sent.above9000 number 0
pktStats.sent.upTo2500 number 0
pktStats.sent.rst number 0
pktStats.sent.synack number 0
pktStats.sent.syn number 0
pktStats.sent.upTo512 number 31
pktStats.sent.upTo9000 number 0
pktStats.sent.upTo1024 number 20
pktStats.sent.upTo6500 number 0
pktStats.sent.upTo64 number 5
has_dropbox_shares boolean false
duration number 1046702
latitude number 43.147899627686
city string 
low_goodput_flows.as_client.anomaly_index number 0
sites.old string { }
udp.packets.rcvd number 1
operatingSystem number 0
low_goodput_flows.as_client number 0
low_goodput_flows.as_server.anomaly_index number 0
num_alerts number 0
tcp.bytes.rcvd number 1860
seen.last number 1561552904
asname string Consortium GARR
anomalous_flows.as_server number 481
other_ip.bytes.rcvd.anomaly_index number 0
packets.rcvd number 571
os string 
total_flows.as_client number 661
country string IT
udp.bytes.sent number 193155
names table
names.dhcp string toprak
names.mdns string toprak
is_multicast boolean false
throughput_trend_bps number 3
broadcast_domain_host boolean true
drop_all_host_traffic boolean false
tcp.bytes.rcvd.anomaly_index number 80
http table
http.receiver table
http.receiver.response table
http.receiver.response.num_2xx number 0
http.receiver.response.num_5xx number 0
http.receiver.response.num_1xx number 0
http.receiver.response.num_3xx number 0
http.receiver.response.total number 0
http.receiver.response.num_4xx number 0
http.receiver.query table
http.receiver.query.num_post number 0
http.receiver.query.num_get number 0
http.receiver.query.num_other number 0
http.receiver.query.num_put number 0
http.receiver.query.total number 0
http.receiver.query.num_head number 0
http.receiver.rate table
http.receiver.rate.response table
http.receiver.rate.response.1xx number 0
http.receiver.rate.response.2xx number 0
http.receiver.rate.response.3xx number 0
http.receiver.rate.response.4xx number 0
http.receiver.rate.response.5xx number 0
http.receiver.rate.query table
http.receiver.rate.query.put number 0
http.receiver.rate.query.other number 0
http.receiver.rate.query.get number 0
http.receiver.rate.query.post number 0
http.receiver.rate.query.head number 0
http.sender table
http.sender.response table
http.sender.response.num_2xx number 0
http.sender.response.num_5xx number 0
http.sender.response.num_1xx number 0
http.sender.response.num_3xx number 0
http.sender.response.total number 0
http.sender.response.num_4xx number 0
http.sender.rate table
http.sender.rate.response table
http.sender.rate.response.1xx number 0
http.sender.rate.response.2xx number 0
http.sender.rate.response.3xx number 0
http.sender.rate.response.4xx number 0
http.sender.rate.response.5xx number 0
http.sender.rate.query table
http.sender.rate.query.put number 0
http.sender.rate.query.other number 0
http.sender.rate.query.get number 0
http.sender.rate.query.post number 0
http.sender.rate.query.head number 0
http.sender.query table
http.sender.query.num_post number 0
http.sender.query.num_get number 0
http.sender.query.num_other number 0
http.sender.query.num_put number 0
http.sender.query.total number 0
http.sender.query.num_head number 0
http.virtual_hosts table
sites string { }
dns table
dns.rcvd table
dns.rcvd.num_replies_ok number 0
dns.rcvd.num_queries number 0
dns.rcvd.queries table
dns.rcvd.queries.num_aaaa number 0
dns.rcvd.queries.num_any number 0
dns.rcvd.queries.num_soa number 0
dns.rcvd.queries.num_txt number 0
dns.rcvd.queries.num_ptr number 0
dns.rcvd.queries.num_a number 0
dns.rcvd.queries.num_other number 0
dns.rcvd.queries.num_mx number 0
dns.rcvd.queries.num_cname number 0
dns.rcvd.queries.num_ns number 0
dns.rcvd.num_replies_error number 0
dns.sent table
dns.sent.num_replies_ok number 0
dns.sent.num_queries number 0
dns.sent.queries table
dns.sent.queries.num_aaaa number 0
dns.sent.queries.num_any number 0
dns.sent.queries.num_soa number 0
dns.sent.queries.num_txt number 0
dns.sent.queries.num_ptr number 0
dns.sent.queries.num_a number 0
dns.sent.queries.num_other number 0
dns.sent.queries.num_mx number 0
dns.sent.queries.num_cname number 0
dns.sent.queries.num_ns number 0
dns.sent.num_replies_error number 0
host_pool_id number 0
tskey string 28:D2:44:73:AC:10_v4
total_activity_time number 20735
udpBytesSent.non_unicast number 1529597
tcp.packets.sent number 0
icmp.bytes.sent number 0
last_throughput_pps number 0.0
other_ip.packets.rcvd number 0
other_ip.bytes.sent number 0
vlan number 0
bytes.sent number 1532259
icmp.packets.rcvd number 0
icmp.packets.sent number 0
udp.bytes.rcvd number 95
unreachable_flows.as_client number 7
low_goodput_flows.as_server number 0
continent string EU
tcp.bytes.sent number 0
anomalous_flows.as_client number 0
hiddenFromTop boolean false
tcp.packets.rcvd number 31
tcp.bytes.sent.anomaly_index number 0
dhcpHost boolean true
contacts.as_server number 0
contacts.as_client number 1
other_ip.bytes.rcvd number 0
udp.bytes.rcvd.anomaly_index number 0
packets.rcvd.anomaly_index number 0
mac string 28:D2:44:73:AC:10
active_http_hosts number 0
bytes.rcvd number 57335
privatehost boolean false
ndpi_categories table
ndpi_categories.Network table
ndpi_categories.Network.bytes.sent number 1469928
ndpi_categories.Network.bytes number 1471903
ndpi_categories.Network.bytes.rcvd number 1975
ndpi_categories.Network.category number 14
ndpi_categories.Network.duration number 15445
ndpi_categories.RPC table
ndpi_categories.RPC.bytes.sent number 0
ndpi_categories.RPC.bytes number 190
ndpi_categories.RPC.bytes.rcvd number 190
ndpi_categories.RPC.category number 16
ndpi_categories.RPC.duration number 10
ndpi_categories.Music table
ndpi_categories.Music.bytes.sent number 58910
ndpi_categories.Music.bytes number 58910
ndpi_categories.Music.bytes.rcvd number 0
ndpi_categories.Music.category number 25
ndpi_categories.Music.duration number 3425
ndpi_categories.System table
ndpi_categories.System.bytes.sent number 1272
ndpi_categories.System.bytes number 1272
ndpi_categories.System.bytes.rcvd number 0
ndpi_categories.System.category number 18
ndpi_categories.System.duration number 25
ndpi_categories.Media table
ndpi_categories.Media.bytes.sent number 0
ndpi_categories.Media.bytes number 60
ndpi_categories.Media.bytes.rcvd number 60
ndpi_categories.Media.category number 1
ndpi_categories.Media.duration number 5
ndpi_categories.Web table
ndpi_categories.Web.bytes.sent number 1551
ndpi_categories.Web.bytes number 1551
ndpi_categories.Web.bytes.rcvd number 0
ndpi_categories.Web.category number 5
ndpi_categories.Web.duration number 5
ndpi_categories.Unspecified table
ndpi_categories.Unspecified.bytes.sent number 598
ndpi_categories.Unspecified.bytes number 55708
ndpi_categories.Unspecified.bytes.rcvd number 55110
ndpi_categories.Unspecified.category number 0
ndpi_categories.Unspecified.duration number 2305
is_broadcast boolean false
ndpi table
ndpi.SNMP table
ndpi.SNMP.bytes.sent number 0
ndpi.SNMP.packets.sent number 0
ndpi.SNMP.bytes.rcvd number 595
ndpi.SNMP.breed string Acceptable
ndpi.SNMP.duration number 35
ndpi.SNMP.packets.rcvd number 595
ndpi.ICMP table
ndpi.ICMP.bytes.sent number 791
ndpi.ICMP.packets.sent number 791
ndpi.ICMP.bytes.rcvd number 60
ndpi.ICMP.breed string Acceptable
ndpi.ICMP.duration number 40
ndpi.ICMP.packets.rcvd number 60
ndpi.Unknown table
ndpi.Unknown.bytes.sent number 459
ndpi.Unknown.packets.sent number 459
ndpi.Unknown.bytes.rcvd number 53250
ndpi.Unknown.breed string Unrated
ndpi.Unknown.duration number 2140
ndpi.Unknown.packets.rcvd number 53250
ndpi.SSL table
ndpi.SSL.bytes.sent number 1551
ndpi.SSL.packets.sent number 1551
ndpi.SSL.bytes.rcvd number 0
ndpi.SSL.breed string Safe
ndpi.SSL.duration number 5
ndpi.SSL.packets.rcvd number 0
ndpi.RX table
ndpi.RX.bytes.sent number 0
ndpi.RX.packets.sent number 0
ndpi.RX.bytes.rcvd number 190
ndpi.RX.breed string Acceptable
ndpi.RX.duration number 10
ndpi.RX.packets.rcvd number 96
ndpi.NetBIOS table
ndpi.NetBIOS.bytes.sent number 552
ndpi.NetBIOS.packets.sent number 552
ndpi.NetBIOS.bytes.rcvd number 0
ndpi.NetBIOS.breed string Acceptable
ndpi.NetBIOS.duration number 10
ndpi.NetBIOS.packets.rcvd number 0
ndpi.Spotify table
ndpi.Spotify.bytes.sent number 58910
ndpi.Spotify.packets.sent number 58910
ndpi.Spotify.bytes.rcvd number 0
ndpi.Spotify.breed string Acceptable
ndpi.Spotify.duration number 3425
ndpi.Spotify.packets.rcvd number 0
ndpi.MDNS table
ndpi.MDNS.bytes.sent number 1469137
ndpi.MDNS.packets.sent number 1276927
ndpi.MDNS.bytes.rcvd number 1320
ndpi.MDNS.breed string Acceptable
ndpi.MDNS.duration number 15405
ndpi.MDNS.packets.rcvd number 1320
ndpi.BJNP table
ndpi.BJNP.bytes.sent number 720
ndpi.BJNP.packets.sent number 484
ndpi.BJNP.bytes.rcvd number 0
ndpi.BJNP.breed string Acceptable
ndpi.BJNP.duration number 15
ndpi.BJNP.packets.rcvd number 0
ndpi.RTP table
ndpi.RTP.bytes.sent number 0
ndpi.RTP.packets.sent number 0
ndpi.RTP.bytes.rcvd number 60
ndpi.RTP.breed string Acceptable
ndpi.RTP.duration number 5
ndpi.RTP.packets.rcvd number 60
localhost boolean true
total_flows.as_server number 507
ifid number 1
asn number 137
childSafe boolean false
is_blacklisted boolean false
tcpPacketStats.sent table
tcpPacketStats.sent.out_of_order number 0
tcpPacketStats.sent.lost number 0
tcpPacketStats.sent.retransmissions number 0
tcpPacketStats.sent.keep_alive number 0
host_unreachable_flows.as_client number 0
host_unreachable_flows.as_server number 0
tcp.packets.seq_problems boolean true
ip string 146.48.99.74
ipkey number 2452644682
icmp.bytes.rcvd.anomaly_index number 0
tcpPacketStats.rcvd table
tcpPacketStats.rcvd.out_of_order number 0
tcpPacketStats.rcvd.lost number 3
tcpPacketStats.rcvd.retransmissions number 48
tcpPacketStats.rcvd.keep_alive number 0
bytes.rcvd.anomaly_index number 0
last_throughput_bps number 0.0
flows.as_client number 661
packets.sent number 6912
pktStats.recv table
pktStats.recv.upTo256 number 0
pktStats.recv.upTo1518 number 0
pktStats.recv.upTo128 number 1
pktStats.recv.finack number 0
pktStats.recv.above9000 number 0
pktStats.recv.upTo2500 number 0
pktStats.recv.rst number 0
pktStats.recv.synack number 0
pktStats.recv.syn number 31
pktStats.recv.upTo512 number 0
pktStats.recv.upTo9000 number 0
pktStats.recv.upTo1024 number 0
pktStats.recv.upTo6500 number 0
pktStats.recv.upTo64 number 31
throughput_pps number 0.0
other_ip.bytes.sent.anomaly_index number 0
active_flows.as_server number 0
udp.bytes.sent.anomaly_index number 67

]]


---------------------------------------------------------------------------------------------------------
---------------------------------------------------------------------------------------------------------

request = google.receive()

if      request.intent_name == "Network_State" then response = handler_Network_State()

elseif  request.intent_name == "Communication_State" then response = handler_network_state_communication()
elseif  request.intent_name == "Communication_State - More_Info" then response = handler_network_state_communication_more_info()

elseif  request.intent_name == "Traffic_App_Info" then response = handler_traffic_app_info()
elseif  request.intent_name == "Traffic_App_Info-More_Info" then response = handler_traffic_app_info_more_info()

elseif  request.intent_name == "UpTime" then response = handler_upTime()

elseif  request.intent_name == "Devices_Info" then response = handler_device_info()
elseif  request.intent_name == "Devices_Info - yes" then response = handler_send_devices_info()

elseif  request.intent_name == "Suspicious_Activity" then response = handler_suspicious_activity()
elseif  request.intent_name == "Suspicious_Activity-More_Info" then response = handler_suspicious_activity_more_info()

elseif  request.intent_name == "Dangerous_communications_detected" then response = handler_dangerous_communications_detected()

elseif  request.intent_name == "ntopng" then response = handler_ntopng()

elseif  request.intent_name == "what_can_you_do" then response = handler_what_can_you_do()

elseif  request.intent_name == "dump" then response = handler_tcp_dump()
elseif  request.intent_name == "send_dump" then response = handler_send_dump()

elseif  request.intent_name == "alert" then response = handler_alert()
elseif  request.intent_name == "alert_more_info" then response = handler_alert_more_info()
elseif  request.intent_name == "alert_from_network_state" then response = handler_alert_more_info()

  --WIP 
elseif request.intent_name == "Devices_Info - fallback" then response = handler_device_info_fallback()



else response = google.send("Scusa, ma non ho capito bene, puoi ripetere?") -- teoricamente questo caso non si pone
end
