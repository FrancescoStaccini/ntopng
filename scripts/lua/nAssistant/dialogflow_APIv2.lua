--
-- (C) 2019 - ntop.org
--

dirs = ntop.getDirs()
package.path = dirs.installdir .. "/scripts/lua/modules/?.lua;" .. package.path
if((dirs.scriptdir ~= nil) and (dirs.scriptdir ~= "")) then package.path = dirs.scriptdir .. "/lua/modules/?.lua;" .. package.path end
ignore_post_payload_parse = 1 

require "lua_utils"
local json = require("dkjson")

sendHTTPContentTypeHeader('Application/json')

--------------------------------------------------------------------------
local debug = true
---------------------------------------------------------------------------
local ga_module = {}
local request = {}
local response = {}

local function fill_response(speech_text, display_text, suggestions_strings, card)  
  if display_text == nil  then display_text = speech_text end
  if expect_response == nil then expect_response = true end

  local mysuggestions, r, myitems = {}, {}, {}

  if suggestions_strings then --note: "suggestions_strings" must be a string array
    for i = 1, #suggestions_strings do
      table.insert( mysuggestions, {title = suggestions_strings[i]} )
    end
  end

  if card then
    myitems =  {  
      { 
        simpleResponse = {
          textToSpeech = speech_text,
          displayText = display_text 
        } 
      },
      {basicCard = card}
    }  
  else
    myitems[1] =  {
      simpleResponse = {
        textToSpeech = speech_text,
        displayText = display_text,
      }
    } 
  end

  r = {
    fulfillmentText = display_text,
    payload = {
      google = {
        expectUserResponse = true,
        richResponse = {
          items = myitems,
          suggestions = mysuggestions
        }
      } 
    }
  }

  if mysuggestions then 
    r.payload.google.richResponse.suggestions = mysuggestions
  end

  local mycontext = ga_module.getContext()

  if mycontext then
    r.outputContexts = mycontext
  end

  ga_module.deleteContext()

  return json.encode(r, {indent = true})
end

--TODO: cards allow many things (like buttons), implement them ---> [ https://dialogflow.com/docs/rich-messages#card ]
--note: in google assistant, the display/speech_text will appear in a bubble over the card
--    "weblink_title" and "button_open_url"_action are optional
-- IMAGE: The height is fixed to 192dp [https://actions-on-google.github.io/actions-on-google-nodejs/classes/conversation_response.basiccard.html]
--NOTE: dentro basiccard= imageDisplayOptions --> https://developers.google.com/actions/reference/rest/Shared.Types/ImageDisplayOptions

--PARAM
  --text: string
  --image: table --> { img_url = X, img_description = X }
  --optional: table --> { title = x, subtitle =X, weblink_title = X, weblink = X } 
function ga_module.create_card(text, image, optional)
  if not image and not text then return nil end--NOTE: image obbligatoria se non c'è il formattedText e viceversa!

  local card, button = {}, {}

  if text then card.formattedText = text end
  if image then card.image = { url = image.img_url, accessibilityText = image.img_description } end

  if optional then 
    local title, subtitle, weblink, weblink_title = optional.title, optional.subtitle, optional.weblink, optional.weblink_title
    if title then card.title = title end
    if subtitle then card.subtitle = subtitle end
  
    if weblink_title and weblink then 
      card.buttons =  { 
        {
          title = weblink_title,
          openUrlAction = { url = weblink}
        } 
      }
    end
  end

  return card
end

--TODO: rifai le fun per i context!? architetturalmente i contesti li tocca solo l'agente dialogflow
--Used to set an arbitrary context (and overwrite the old one) call setContext()
--For complex structures use as many prefs as there are fields to save
function ga_module.setContext(name, lifespan, parameter) 

  if name then 
    ntop.setCache("context_name", name, 60 * 20) --(max context lifespan: 20 min)
  end
  if lifespan then 
    ntop.setCache("context_lifespan", tostring(lifespan), 60 * 20)
  end

  if parameter then 
    ntop.setCache("context_param", parameter, 60 * 20)
  end
end

function ga_module.deleteContext()
  ntop.delCache("context_name")
  ntop.delCache("context_lifespan")
  ntop.delCache("context_param")
end

function ga_module.getContext()

  local name = ntop.getCache("context_name")
  if name == "" then return nil end
  
  local lifespan = ntop.getCache("context_lifespan")

  if lifespan == "" then lifespan = 2 end

  local mycontext = {
    {
      name = name,
      lifespanCount = lifespan,
      parameters = {param = ntop.getCache("context_param") }
    }
  }

  return mycontext
end


--TODO!: rifai a modo la send, tenendo conto dei componeni non implementati.
  --    metti solo i parametri obbligatori e in "optional" il resto

--[[PARAM
  speech_text, diplay_text: self explanatory
  expect_response: boolean to let the assistant listen
  suggestions_strings: suggestions displayed on the bottom of the screen (MAX 8)
  (basic)card: one of the "rich message" response [https://dialogflow.com/docs/intents/rich-messages]
  ]]

--idea: metto tra i parametri i campi che uso spesso, in optional le altre varie ed eventuali da implementare
--function ga_module.send(speech_text, display_text, expect_response, suggestions_strings, card )
function ga_module.send(speech_text, display_text, suggestions_strings, card, optional )

  if suggestions_strings then 
    for i,v in pairs(suggestions_strings) do 
      if string.len(v) > 25 then
        suggestions_strings[i] = string.sub(v,1,25)   --note: Suggestions chip must not be longer than 25 characters.
      end
    end
  end

  res = fill_response(speech_text, display_text, suggestions_strings, card)
  print(res.."\n")

    if debug then 
      io.write("\n")
      io.write("NTOPNG RESPONSE\n")
      tprint(res)
      io.write("\n---------------------------------------------------------\n")
    end
end

--DIALOGFLOW REQUEST EXAMPLE:
 --[[
   dialogflow request: Default Welcome Intent (SIMULATORE - phone)

 {
  "responseId": "fb4882ed-3826-4ea9-9cb7-4abe47efb88a-2a4c0c5e",
  "queryResult": {
    "queryText": "GOOGLE_ASSISTANT_WELCOME",
    "action": "input.welcome",
    "parameters": {
    },
    "allRequiredParamsPresent": true,
    "fulfillmentText": "Hello! What do you want to know about your network?",
    "fulfillmentMessages": [{
      "text": {
        "text": ["Hello! What do you want to know about your network?"]
      }
    }],
    "outputContexts": [{
      "name": "projects/nassistant02-qbmwmv/agent/sessions/ABwppHHFEUZ0n4OextFk2WXwY0w1T1CFpInJ-kJnfnvuh1cJmXEkgQrmetaijJl88IkTWtDryG8UuBtesBtf8qTQUg/contexts/actions_capability_web_browser"
    }, {
      "name": "projects/nassistant02-qbmwmv/agent/sessions/ABwppHHFEUZ0n4OextFk2WXwY0w1T1CFpInJ-kJnfnvuh1cJmXEkgQrmetaijJl88IkTWtDryG8UuBtesBtf8qTQUg/contexts/actions_capability_media_response_audio"
    }, {
      "name": "projects/nassistant02-qbmwmv/agent/sessions/ABwppHHFEUZ0n4OextFk2WXwY0w1T1CFpInJ-kJnfnvuh1cJmXEkgQrmetaijJl88IkTWtDryG8UuBtesBtf8qTQUg/contexts/actions_capability_audio_output"
    }, {
      "name": "projects/nassistant02-qbmwmv/agent/sessions/ABwppHHFEUZ0n4OextFk2WXwY0w1T1CFpInJ-kJnfnvuh1cJmXEkgQrmetaijJl88IkTWtDryG8UuBtesBtf8qTQUg/contexts/actions_capability_account_linking"
    }, {
      "name": "projects/nassistant02-qbmwmv/agent/sessions/ABwppHHFEUZ0n4OextFk2WXwY0w1T1CFpInJ-kJnfnvuh1cJmXEkgQrmetaijJl88IkTWtDryG8UuBtesBtf8qTQUg/contexts/actions_capability_screen_output"
    }, {
      "name": "projects/nassistant02-qbmwmv/agent/sessions/ABwppHHFEUZ0n4OextFk2WXwY0w1T1CFpInJ-kJnfnvuh1cJmXEkgQrmetaijJl88IkTWtDryG8UuBtesBtf8qTQUg/contexts/google_assistant_input_type_keyboard"
    }, {
      "name": "projects/nassistant02-qbmwmv/agent/sessions/ABwppHHFEUZ0n4OextFk2WXwY0w1T1CFpInJ-kJnfnvuh1cJmXEkgQrmetaijJl88IkTWtDryG8UuBtesBtf8qTQUg/contexts/google_assistant_welcome"
    }],
    "intent": {
      "name": "projects/nassistant02-qbmwmv/agent/intents/e3f5e886-5abc-48f4-a685-9ea8d8244039",
      "displayName": "Default Welcome Intent"
    },
    "intentDetectionConfidence": 1.0,
    "languageCode": "en"
  },
  "originalDetectIntentRequest": {
    "source": "google",
    "version": "2",
    "payload": {
      "user": {
        "locale": "en-US",
        "lastSeen": "2019-10-03T10:52:43Z",
        "userVerificationStatus": "VERIFIED"
      },
      "conversation": {
        "conversationId": "ABwppHHFEUZ0n4OextFk2WXwY0w1T1CFpInJ-kJnfnvuh1cJmXEkgQrmetaijJl88IkTWtDryG8UuBtesBtf8qTQUg",
        "type": "NEW"
      },
      "inputs": [{
        "intent": "actions.intent.MAIN",
        "rawInputs": [{
          "inputType": "KEYBOARD",
          "query": "Talk to nAssistant two"
        }]
      }],
      "surface": {
        "capabilities": [{
          "name": "actions.capability.WEB_BROWSER"
        }, {
          "name": "actions.capability.MEDIA_RESPONSE_AUDIO"
        }, {
          "name": "actions.capability.AUDIO_OUTPUT"
        }, {
          "name": "actions.capability.ACCOUNT_LINKING"
        }, {
          "name": "actions.capability.SCREEN_OUTPUT"
        }]
      },
      "isInSandbox": true,
      "availableSurfaces": [{
        "capabilities": [{
          "name": "actions.capability.AUDIO_OUTPUT"
        }, {
          "name": "actions.capability.WEB_BROWSER"
        }, {
          "name": "actions.capability.SCREEN_OUTPUT"
        }]
      }],
      "requestType": "SIMULATOR"
    }
  },
  "session": "projects/nassistant02-qbmwmv/agent/sessions/ABwppHHFEUZ0n4OextFk2WXwY0w1T1CFpInJ-kJnfnvuh1cJmXEkgQrmetaijJl88IkTWtDryG8UuBtesBtf8qTQUg"
}
 ]] 

--TODO: voglio che il precedente (NON attuale) contesto sia a disposizione
function ga_module.receive()
  local payload = _POST["payload"] 
  local info, pos, err = json.decode(payload, 1, nil)
  --WIP: volgio in pratica passare direttamente la richiesta decodificata, qui solo gestione errori, cache etc

  --TODO: gestione cache! es:salvo info per l'intent successivo. sì, ciò spezza un pò l'architettura che creo su dialogflow,
      --  la quale coi strumenti della piattaforma dovrebbe saper direzionare il dialogo.

    if debug then   
      io.write("\n")
      io.write("DIALOGFLOW REQUEST")
      tprint(payload)
      io.write("\n---------------------------------------------------------\n")
    end

  return info
end

return ga_module
