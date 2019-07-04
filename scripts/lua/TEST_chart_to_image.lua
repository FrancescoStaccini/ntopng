


-- https://quickchart.io   GLI FAI UNA POST COI DATI E TI RESTITUISCE UN'IMMAGINE CON IL GRAFICO
--NOTE: There is a 240 requests per minute per IP rate limit (4 charts/sec) on the public service.

--Also, i can create QR code


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
local net_state = require "network_state"

sendHTTPContentTypeHeader('text/html')

local test_str = "{type:'bar',data:{labels:['January','February','March','April','May'],datasets:[{label:'Dogs',data:[50,60,70,180,190]},{label:'Cats',data:[100,200,300,400,500]}]}}"


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
_______________________________________________________________________

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
________________________________________________

MEGATODO:   POST endpoint   (https://quickchart.io/#build-from-url)
If your chart is large or complicated, you may prefer to send a POST request rather than a GET request. This avoids limitations on URL length and means you don't have to worry about URL encoding. The /chart POST endpoint takes the same parameters as above via the following JSON object:

        {
          "backgroundColor": "transparent",
          "width": 500,
          "height": 300,
          "chart": {...},
        }
      
Note that if you want to include Javascript options in chart, you'll have to send the parameter as a string rather than a JSON object. 


ELEMENTI DELLA CARD:
    local display_text = "CIAO SONO GEORGE"
    local speech_text = "WOF WOF"
    local card_title = "Giorgione"
    local card_url_image = "https://drive.google.com/open?id=1-EezgVe6jV0fjUVLYcRyKTuS2RF9jTEN"
    local accessibility_text = "cane"
    local button_title = "corgi butt?"
    local button_open_url_action = "https://encrypted-tbn0.gstatic.com/images?q=tbn:ANd9GcQvmiwQzR_ihGRYwyl9ifunUyTwoGI8nv7yvlyg4B4yV41MeNoNPQ"
   


]]



  
