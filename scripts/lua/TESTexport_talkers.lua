--
-- (C) 2013-19 - ntop.org
--
local dirs = ntop.getDirs()
package.path = dirs.installdir .. "/scripts/lua/modules/timeseries/?.lua;" .. package.path


local ts_utils = require "ts_utils_core"

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

V# Extract last hour interface traffic (change ifid:1 accordingly)
curl -s --cookie "user=admin; password=admin" "http://127.0.0.1:3000/lua/rest/get/timeseries/ts.lua?ts_schema=iface:traffic&ts_query=ifid:1&extended=1"

# Extract host traffic in the specified time frame
curl -s --cookie "user=admin; password=admin" "http://127.0.0.1:3000/lua/rest/get/timeseries/ts.lua?ts_schema=host:traffic&ts_query=ifid:1,host:192.168.1.10&epoch_begin=1532180495&epoch_end=1532176895&extended=1"

# Extract last hour top host protocols
curl -s --cookie "user=admin; password=admin" "http://127.0.0.1:3000/lua/rest/get/timeseries/ts.lua?ts_schema=top:host:ndpi&ts_query=ifid:1,host:192.168.43.18&extended=1"

# Extract last hour AS 62041 RTT
curl -s --cookie "user=admin; password=admin" "http://127.0.0.1:3000/lua/rest/get/timeseries/ts.lua?ts_query=ifid:1,asn:62041&ts_schema=asn:rtt&extended=1"

]]


local res = ts_utils.query("mac:local_talkers_work_devices", {
    ifid = "3",
    --host = "192.168.1.10",
    mac = "FF:FF:FF:FF:FF:FF",
    },
    os.time()-3600, os.time()
)
  
tprint(res)


