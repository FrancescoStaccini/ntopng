
dirs = ntop.getDirs()
package.path = dirs.installdir .. "/scripts/lua/?.lua;" .. package.path
if((dirs.scriptdir ~= nil) and (dirs.scriptdir ~= "")) then package.path = dirs.scriptdir .. "/lua/modules/?.lua;" .. package.path end
require "lua_utils"

local ts_utils = require "ts_utils"
local json = require("dkjson")

sendHTTPContentTypeHeader('Application/json')



local host_info = url2hostinfo(_GET)


local mac = "FF:FF:FF:FF:FF:FF"--4test

if host_info.host then
    mac = host_info["host"]
    io.write("\nmac: " .. mac .. "\n")
end


-- if mac then 

--     local schema = "mac:local_talkers_work_devices"
--     local tags = {mac = mac, ifid = 3 }
--     local start_time = os.time() - 3600 * 6
--     local end_time = os.time()
--     io.write("-----------------------------------------------\n")
--     io.write("\n[DEBUG] -query parameters- schema:\n")
--     tprint(schema)
--     io.write("tags:\n")
--     tprint(tags)
--     io.write("\n")
--     io.write("start time= "..start_time.."\n")
--     io.write("end time= "..end_time.."\n")
--     io.write("-----------------------------------------------\n")


--     local res = ts_utils.query(schema, tags, start_time, end_time)

--     print( json.encode( res, {indent = true} ) ) 

-- -------------------------------------------------------------------------

--     local schema = "mac:local_talkers_unknow_devices"
--     local tags = {mac = mac, ifid = 3 }
--     local start_time = os.time() - 3600 * 6
--     local end_time = os.time()
--     io.write("-----------------------------------------------\n")
--     io.write("\n[DEBUG] -query parameters- schema:\n")
--     tprint(schema)
--     io.write("tags:\n")
--     tprint(tags)
--     io.write("\n")
--     io.write("start time= "..start_time.."\n")
--     io.write("end time= "..end_time.."\n")
--     io.write("-----------------------------------------------\n")


--     local res = ts_utils.query(schema, tags, start_time, end_time)

--     print( json.encode( res, {indent = true} ) )


-- else 
--     print( "host not found" )
-- end
--tprint(res)

--[[
    
ESEMPIO API LUA

local res = ts_utils.query("host:ndpi", {
  ifid = "1",
  host = "192.168.1.10",
  protocol = "Facebook"
}, os.time()-3600, os.time())
--tprint(res)

+++++++++++++++++++++++++++++++++++++++++++++++++++

ESEMPIO VIA CURL (sw esterno)
{
    V# Extract last hour interface traffic (change ifid:1 accordingly)
    curl -s --cookie "user=admin; password=admin" "http://127.0.0.1:3000/lua/rest/get/timeseries/ts.lua?ts_schema=iface:traffic&ts_query=ifid:1&extended=1"

    # Extract host traffic in the specified time frame
    curl -s --cookie "user=admin; password=admin" "http://127.0.0.1:3000/lua/rest/get/timeseries/ts.lua?ts_schema=host:traffic&ts_query=ifid:1,host:192.168.1.10&epoch_begin=1532180495&epoch_end=1532176895&extended=1"

    # Extract last hour top host protocols
    curl -s --cookie "user=admin; password=admin" "http://127.0.0.1:3000/lua/rest/get/timeseries/ts.lua?ts_schema=top:host:ndpi&ts_query=ifid:1,host:192.168.43.18&extended=1"

    # Extract last hour AS 62041 RTT
    curl -s --cookie "user=admin; password=admin" "http://127.0.0.1:3000/lua/rest/get/timeseries/ts.lua?ts_query=ifid:1,asn:62041&ts_schema=asn:rtt&extended=1"
}
]]





