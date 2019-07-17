--
-- (C) 2019 - ntop.org
--
-- Genreic Utils & Language Utils

dirs = ntop.getDirs()
package.path = dirs.installdir .. "/scripts/lua/modules/?.lua;" .. package.path
if((dirs.scriptdir ~= nil) and (dirs.scriptdir ~= "")) then package.path = dirs.scriptdir .. "/lua/modules/?.lua;" .. package.path end
require "lua_utils"
local json = require("dkjson")

local utils = {}

--TODO: controlla se è già presente in ntop una funzione simile
function utils.url_encode(str)
    if str then
        str = str:gsub("\n", "\r\n")
        str = str:gsub("([^%w %-%_%.%~])", function(c)
        return ("%%%02X"):format(string.byte(c))
        end)
        str = str:gsub(" ", "+")
    end
    return str	
end


function utils.create_top_traffic_speech_text(top_app)
    local text, top_num, j = "", 0, 1
    local app_names, app_perc = {}, {}

    for i,v in pairs(top_app) do
      tprint(i)
      tprint(v)
      table.insert(app_names, v.name)
      table.insert(app_perc, v.percentage)
      top_num = top_num + 1
      if top_num == 3 then break end
    end
    --NOTE:tiene conto solo dei primi 3 proto per una questione di pesantezza cognitiva: l'assistente non deve parlare troppo 
    if top_num == 1 then 
      text = "I note only "..app_names[1].." with "..app_perc[1] .." % of traffic."
    end
  
    local text_name, text_perc
    if top_num > 1 then 
      text_name = "The ".. top_num .." main applications are: "..app_names[1]..", "..app_names[2].. ternary(app_names[3], ", and "..app_names[3], "" ) 
      text_perc = "; With a traffic, respectively, of "..app_perc[1]..", "..app_perc[2].. ternary(app_perc[3], ", "..app_perc[3], "" ) .. " %"
      text = text_name..text_perc
    else 
      text = "No application deteced" 
    end
    
    return text 
end


--TODO: fai meglio le utils per i chart, dallo script dell'assistente voglio solo passare una tabella con le opzioni e un paio di array per i dati e bona


--NOTE: per ora funge col grafico a barre con UNA SOLA entità per punto
--TODO: a lot! le possibili opzioni sono taaante

--PARAMETER: data must contaim 3 field: labels = dell'asse X; values = di Y; legend_label = the legend;
--          options must contain 4 field: bkg_color = background color; w = width; h = height; chart_type = the type of the chart
function utils.create_chart_url(data, options)
    local w,h,site_name = options.w, options.h, "https://quickchart.io/chart?" --TODO: indaga sulle possibili dim dell'img (mantenere un certo rapporto tra w e h?)
    local chart_type = options.chart_type --also Radar, Line, Pie, Doughnut, Scatter, Bubble, Radial, Sparklines, Mixed
    local bkg_color = options.bkg_color
    --local option = ""--check docs (chart.js) because that's a loooot of stuff (a lot of plugins like Annotation)
    --local legend = false

    --TODO: support for more options, bars, type ecc...
    --currently the bar-chart support only ONE bar per point
    local c = {
        type = options.chart_type,
        data = {
            labels = data.labels,--labels deve essere un array di valori
            datasets = {{--datasets deve essere un array di valori
                label = data.legend_label,  
                data = data["values"] --(inner)data deve essere un array di valori
            }}
        }
    }
    if options.chart_type == "outlabeledPie" then 
        c["options"] = {
            plugins = {
              legend = false,
              outlabels = {
                text = "%l %p",
                color = "white",
                stretch = 35,
                font = {
                  resizable = true,
                  minSize = 12,
                  maxSize = 18
                }
              }
            }
          }
    end

    local jn = json.encode(c)

    tprint(jn)

    local url = ""
    if options.chart_type == "outlabeledPie" then 
        url = site_name.."bkg=".. bkg_color.."&c="..utils.url_encode(jn)
    else
        url = site_name.."w="..w.."&h="..h.."&bkg=".. bkg_color.."&c="..utils.url_encode(jn)
    end

    return url
end




---------------
return utils


-- {
--   "data":{
--     "labels":["Unspecified","Network","Cloud","Web","System","Email"],
--     "datasets":[{
--       "data":[4509.6435546875,1070.927734375,893.7392578125,618.6279296875,113.142578125,42.2421875],
--       "label":"Traffic (KB)"
--     }]
--   },
--   "type":"bar"
-- }

--[[
cosi ho creato il json per esportare i proto e meterli come entity

local t = {}
for i,v in pairs(interface.getnDPIProtocols()) do 
    table.insert(t,{value = i, synonyms = {i} })
end
--ho rimosso a mano "sina(weibo)" perchè Dialogflow non vuole parentesi
]]