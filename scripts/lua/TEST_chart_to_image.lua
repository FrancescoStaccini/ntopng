


-- https://quickchart.io   GLI FAI UNA POST COI DATI E TI RESTITUISCE UN'IMMAGINE CON IL GRAFICO, SBEM


--os.execute("curl -X POST  https://api.telegram.org/bot"..bot_token.."/sendMessage -d chat_id="..chat_id.." -d text=\" " ..text.." \" ")

 --[[
  --ESEMPIO FUNZIONANTE:
 
    curl -X GET -H "Content-Type: application/json" -g "https://quickchart.io/chart?width=500&height=300&backgroundColor=white&c={type:%27bar%27,data:{labels:[%27January%27,%27February%27,%27March%27,%27April%27,%20%27May%27],%20datasets:[{label:%27Dogs%27,data:[50,60,70,180,190]},{label:%27Cats%27,data:[100,200,300,400,500]}]}}" -o imggg^
  
    note: ho fatto vari test per riuscuire a passare i dati nel body della GET ma nulla 
    ora, in teoria mi basta creare la URL a modo, poi la passo a Dialogfow e sarà lui e reperire la foto
    ]]


dirs = ntop.getDirs()
package.path = dirs.installdir .. "/scripts/lua/?.lua;" .. package.path
if((dirs.scriptdir ~= nil) and (dirs.scriptdir ~= "")) then package.path = dirs.scriptdir .. "/lua/modules/?.lua;" .. package.path end
--ignore_post_payload_parse = 1
require "lua_utils"
local json = require("dkjson")

sendHTTPContentTypeHeader('text/html')

local test_str = "{type:'bar',data:{labels:['January','February','March','April','May'],datasets:[{label:'Dogs',data:[50,60,70,180,190]},{label:'Cats',data:[100,200,300,400,500]}]}}"

--TODO: controlla se è già presente in ntop una funzione simile
function url_encode(str)
    if str then
        str = str:gsub("\n", "\r\n")
        str = str:gsub("([^%w %-%_%.%~])", function(c)
        return ("%%%02X"):format(string.byte(c))
        end)
        str = str:gsub(" ", "+")
    end
    return str	
end

--print(  url_encode(test_str)    )

--IDEA: fai l'encode in json, poi l'url encode

--[[ esempio  url payload
    {
  type: 'bar',
  data: {
    labels: ['January', 'February', 'March', 'April', 'May'],
    datasets: [{
      label: 'Dogs',
      data: [ 50, 60, 70, 180, 190 ]
    }, {
      label: 'Cats',
      data: [ 100, 200, 300, 400, 500 ]
    }]
  }
}
-----------------------------------------------------------------

  type: 'bar',
  data: {
    labels: ['January', 'February', 'March', 'April', 'May'],
    datasets: [{
      label: 'Dogs',
      backgroundColor: 'chartreuse',
      data: [ 50, 60, 70, 180, 190 ]
    }, {
      label: 'Cats',
      backgroundColor: 'gold',
      data: [ 100, 200, 300, 400, 500 ]
    }]
  },
  options: {
    title: {
      display: true,
      text: 'Total Revenue (billions)',
      fontColor: 'hotpink',
      fontSize: 32,
    },
    legend: {
      position: 'bottom',
    },
    scales: {
      xAxes: [{stacked: true}],
      yAxes: [{
        stacked: true,
        ticks: {
          callback: function(value) {
            return '$' + value;
          }
        }
      }],
    },
    plugins: {
      datalabels: {
        display: true,
        font: {
          style: 'bold',
        },
      },
    },
  },
}

]]

function create_graph_url(type, data, datasets)
    local w,h,site_name = 500, 280, "https://quickchart.io/chart?"
    local chart type = "bar" --also Radar, Line, Pie, Doughnut, Scatter, Bubble, Radial, Sparklines, Mixed
    local option = ""--check docs because that's a lot of stuff
    




    


end






  
