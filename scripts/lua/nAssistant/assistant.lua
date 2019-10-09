--
-- (C) 2019 - ntop.org
--
dirs = ntop.getDirs()
package.path = dirs.installdir .. "/scripts/lua/?.lua;" .. package.path
if((dirs.scriptdir ~= nil) and (dirs.scriptdir ~= "")) then package.path = dirs.scriptdir .. "/lua/modules/?.lua;" .. package.path end
ignore_post_payload_parse = 1

local dialogflow = require "nAssistant/dialogflow_APIv2"
local handlers = require "nAssistant/handlers"

local user_request, ntop_response = dialogflow.receive(), {}
------------------------
------------------------

if      user_request.queryResult.intent.displayName == "get_aggregated_info" then
    ntop_response = handlers.get_aggregated_info(user_request)

elseif  user_request.queryResult.intent.displayName == "get_aggregated_info - repeat" then
    ntop_response = handlers.get_aggregated_info(user_request) --TODO

elseif  user_request.queryResult.intent.displayName == "get_aggregated_info - more" then
    ntop_response = handlers.get_aggregated_info_more(user_request) --TODO

------------------------
elseif  user_request.queryResult.intent.displayName == "if_active_flow_top_application" then
    ntop_response = handlers.if_active_flow_top_application(user_request)

elseif  user_request.queryResult.intent.displayName == "if_active_flow_top_categories"  then
    ntop_response = handlers.if_active_flow_top_categories(user_request)

------------------------
elseif  user_request.queryResult.intent.displayName == "who_is - categories" then
    ntop_response = handlers.who_is_categories(user_request)

elseif  user_request.queryResult.intent.displayName == "who_is - protocols"  then
    ntop_response = handlers.who_is_protocols(user_request)--WIP, non va! TODO!

------------------------
--CHECK: nuovo contesto per gli "who_is" così da poter triggerare l'individuazione del nome dell'host/device da lì (es tappando sul suggerimento)
elseif  user_request.queryResult.intent.displayName == "ask_for_single_device_info - fallback" then
    ntop_response = handlers.device_info(user_request)

elseif  user_request.queryResult.intent.displayName == "ask_for_single_device_info - fallback - more" then
    ntop_response = handlers.device_info_more(user_request)

------------------------
--TODO: sarebbe meglio fare altri intent per il "who_is..." che parte dalle info del singolo device e non da "top_..."
elseif  user_request.queryResult.intent.displayName == "who_is - categories - fallback" then
    ntop_response = handlers.device_info(user_request)

elseif  user_request.queryResult.intent.displayName == "who_is - protocols - fallback" then
    ntop_response = handlers.device_info(user_request) 

------------------------
elseif  user_request.queryResult.intent.displayName == "get_security_info" then
    ntop_response = handlers.get_security_info(user_request)

elseif  user_request.queryResult.intent.displayName == "get_security_info - fallback" then
    ntop_response =handlers.host_info(user_request) 

elseif  user_request.queryResult.intent.displayName == "get_security_info - fallback - more" then
    ntop_response = handlers.host_info_more(user_request)

------------------------
elseif  user_request.queryResult.intent.displayName == "get_suspected_host_info" then
    ntop_response = handlers.get_most_suspected_host_info(user_request)

elseif  user_request.queryResult.intent.displayName == "get_host_misbehaving_flows_info" then
    ntop_response = handlers.get_host_misbehaving_flows_info(user_request) 

--TODO: 
elseif  user_request.queryResult.intent.displayName == "get_ghost_network_info" then
    ntop_response = handlers.get_ghost_network_info(user_request)

else ntop_response = dialogflow.send("Sorry, but I didn't understand, can you repeat please?") 
end

--TODO: controllo errori?! roba cache qui? tipo salvo i dati diquesta user_request solo ora,
--      così che durante l'elaborazione dell'intent in cache c'era il precedente

dialogflow.send(
    ntop_response.speech_text,
    ntop_response.display_text,
    ntop_response.suggestions,
    ntop_response.card
)

--[[

    ntop_response.speech_text =  text 
    return ntop_response



  ntop_response.speech_text = speech_text
  ntop_response.display_text = display_text
  ntop_response.suggestions = sugg    
  ntop_response.card = card

  return ntop_response

]]