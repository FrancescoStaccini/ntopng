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

--TODO: poi spostalo
local json = require("dkjson")

local response, request

--TODO: CANCELLA I VECCHI FILE: google_assistant_utils.lua ecc.


--TODO: RICH MESSAGE!!!! [ https://cloud.dialogflow.com/dialogflow/docs/intents-rich-messages ] inoltre esempi json tra i preferiti
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

    
    dialogflow.send()
end


function handler_test()

    local data = {}--graph data (labels and datasets)

    local w,h,site_name = 500, 280, "https://quickchart.io/chart?" --TODO: indaga sulle possibili dim dell'img (mantenere un certo rapporto tra w e h?)
    local chart_type = "bar" --also Radar, Line, Pie, Doughnut, Scatter, Bubble, Radial, Sparklines, Mixed
    local bkgColor = "white"
    local option = ""--check docs because that's a lot of stuff (a lot of plugins like Annotation)
    local legend = false


    local pre_data = net_state.check_top_application_protocol()
    --[[
        pre_data:

         table
            1 table
                1.1 string Dropbox
                1.2 number 45
            2 table
                2.1 string SSL
                2.2 number 15
            3 table
                3.1 string VRRP
                3.2 number 12
            4 table
                4.1 string MDNS
                4.2 number 10
            .
            .
            .
    ]]

    local tmp_str = ""
    local labels = {}
    local values = {}
    local datasets = {}

    local i = 0 
    for _,v in ipairs(pre_data) do
        table.insert(labels, v[1])
        table.insert(values, v[2] )
        i = i + 1
        if i > 6 then break end
    end

    --bar structure for ONE bar per point
    local c = {
        type = chart_type,
        data = {
            labels = labels,--labels deve essere un array di valori
            datasets = {--datasets deve essere un array di valori
                --label = "nome"  per ora lo ignoro in quanto non comparo due barre
                data = values --(inner)data deve essere un array di valori
            }
        }
    }

    local jn = json.encode(c)

    tprint(jn)

    -- local card = dialogflow.create_card(
    --     "Card Title",
    --     "HERE CHART URL",
    --     "here accessibility text",
    --     "btn title", --optional
    --     "btn link" --optional
    -- )
    -- dialogflow.send("hey", nil, nil, nil, card)

    dialogflow.send("hey")
end


--######################################################################################################################################
request = dialogflow.receive()

if      request.intent_name == "get_aggregated_info" then response = handler_get_aggregated_info()

elseif  request.intent_name == "test" then response = handler_test()

else response = dialogflow.send("Sorry, but I didn't understand, can you repeat?") 
end