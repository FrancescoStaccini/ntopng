--TEST ABOUT PRINTING A PIE-CHART FROM DATA OF A SPECIFIC DEVICES/HOST, AND TRANSFORM THAT CHART INTO AN IMAGE


--NOPE! CAMBIO STRATEGIA, NON POSSO USARE GLI SCRIPT JS PERCHÉ INTERPRETATI DAL BROWSER
--  ED IL BROWSER NON CI CAVA NULLA QUI! È UNA QUESTIONE NTOP/LUA E DIALOGFLOW

--SOLUZIONE?  https://quickchart.io   GLI FAI UNA POST COI DATI E TI RESTITUISCE UN'IMMAGINE CON IL GRAFICO, SBEM


--WIP prova la curl sul terminale

--os.execute("curl -X POST  https://api.telegram.org/bot"..bot_token.."/sendMessage -d chat_id="..chat_id.." -d text=\" " ..text.." \" ")

 --[[

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

sendHTTPContentTypeHeader('text/html')


local json = require("dkjson")


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


  print( json.encode( "[prova] labels: ['January', 'February', 'March', 'April', 'May']," , {indent = true} ) )
  print( json.encode( "[encoded] " .. url_encode("labels: ['January', 'February', 'March', 'April', 'May'],")  , {indent = true} ) )




  
