--
-- (C) 2019 - ntop.org
--
dirs = ntop.getDirs()
package.path = dirs.installdir .. "/scripts/lua/?.lua;" .. package.path
if((dirs.scriptdir ~= nil) and (dirs.scriptdir ~= "")) then package.path = dirs.scriptdir .. "/lua/modules/?.lua;" .. package.path end
ignore_post_payload_parse = 1 

require "lua_utils"
local dialogflow = require "nAssistant/dialogflow_APIv2"
local alexa = require "nAssistant/alexaAPI"

local driver = {}

local debug = true

--#########################################################################

--type: "df" or "aa" (dialogfow / amazon alexa)

local function driver.generate_response(type, info)
    local res = {}

    if not (type and info) then return nil end

    if      type == "df" then res = dialogflow.create_json_response(info)
    elseif  type == "aa" then res = alexa.create_json_response(info)
    
    return res
end

--#########################################################################

function driver.send(info)
    local res = {}

    --TODO: 

    return res
end

--#########################################################################

function driver.receive()
    local payload = _POST["payload"] 
    local info, pos, err = json.decode(payload, 1, nil)
  
      if debug then   
        io.write("\n")
        io.write("---------DIALOGFLOW REQUEST----------")
        tprint(payload)
        io.write("\n-----------------------------------\n")
      end

      if info and info.responseId then 
        res = compose_dialogflow_request(info)
      else
        res = compose_alexa_request(info)
      end

      --TODO: implementa modello standard della richiesta
      return res
  
    return info
end

--#########################################################################

local function compose_dialogflow_request(info)
--TODO
end

--#########################################################################


local function compose_alexa_request(info)
    --TODO
end

--#########################################################################
