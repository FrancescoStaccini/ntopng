--
-- (C) 2019 - ntop.org
--
dirs = ntop.getDirs()
package.path = dirs.installdir .. "/scripts/lua/?.lua;" .. package.path
if((dirs.scriptdir ~= nil) and (dirs.scriptdir ~= "")) then package.path = dirs.scriptdir .. "/lua/modules/?.lua;" .. package.path end
ignore_post_payload_parse = 1

require "lua_utils"
local assistant = require "google_assistant_utils"
local net_state = require "network_state"

local response, request


--TODO: RICH MESSAGE!!!! [ https://cloud.google.com/dialogflow/docs/intents-rich-messages ] inoltre esempi json tra i preferiti
--idea: nell'URL dell'immagine metto il link al(lo scriptino lua nel) server ntop con alla fine i parametri 
--      necessari per fare il grafico

function handler_get_aggregated_info()
    local response_text = ""
    local tips = {}


    --prendo i param per vedere se è Devices, Network, Traffic, Generic
    local aggregator = request.parameters.TODO


    --gestisco i 4 differenti casi
    if aggregator == "Generic" then 

    elseif aggregator == "Traffic" then 

    elseif aggregator == "Network" then

    elseif aggregator == "Devices" then
    
    else

         --[[fallback]]

    end

    



    assistant.send()
end


--######################################################################################################################################
request = assistant.receive()

if      request.intent_name == "get_aggregated_info" then response = handler_get_aggregated_info()

--elseif  request.intent_name == "Communication_State" then response = handler_network_state_communication()

else response = google.send("Sorry, but I didn't understand, can you repeat?") -- teoricamente questo caso non si pone
end