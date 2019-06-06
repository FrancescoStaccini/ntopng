--
-- (C) 2013-19 - ntop.org
--

local dirs = ntop.getDirs()
package.path = dirs.installdir .. "/scripts/lua/modules/?.lua;" .. package.path
require "lua_utils"
local discover = require "discover_utils"
local ts_utils = require "ts_utils_core"

local arpMatrixModule = {}
local debug = false

--the callback will be executed for each element of the matrix,
--and every result will be added to the table that will be returned
function arpMatrixModule.matrixWalk(callback)
    local matrix = interface.getArpStatsMatrixInfo()
    if not matrix then return false end
    local src_ip, dst_ip, src_mac, dst_mac
    local t = {}

    for _, m_elem in pairs(matrix) do
        for i, stats in pairs(m_elem)do
            tmp = split(i,"-")
            src_ip = tmp[1]
            dst_ip = tmp[2]
            src_mac = stats["src_mac"]
            dst_mac = stats["dst_mac"]

            table.insert( t, callback(src_ip, dst_ip, src_mac, dst_mac, stats) )
        end
    end
    return t
end

--return the number of dumped element
function arpMatrixModule.dumpArpMatrix(ifnm)
    local matrix = interface.getArpStatsMatrixInfo()
    if not matrix then return 0 end
    local src_ip, dst_ip, src_mac, dst_mac, tot, id, ifn
    local cont = 0

    for _, m_elem in pairs(matrix) do
        for i, stats in pairs(m_elem)do
            tmp = split(i,"-")
            src_ip = tmp[1]
            dst_ip = tmp[2]
            src_mac = stats["src_mac"]
            dst_mac = stats["dst_mac"]

            tot = stats["src2dst.requests"] + stats["src2dst.replies"] + stats["dst2src.requests"] + stats["dst2src.replies"]
            id = src_ip.."-"..dst_ip.."-"..src_mac.."-"..dst_mac 
            ifn = getInterfaceId(ifnm)
    
            ts_utils.append("host_pair:arp_communication", {ifid = ifn, protocol = "arp", id = id, num_packets = tot}, when, verbose)
            cont = cont + 1

            io.write(cont.." - if: ".. ifn .." id: "..id.." - "..tot.."\n")
        end
    end
    return cont
end

--check if that host have sent some pkts
function arpMatrixModule.arpCheck(host_ip)
    local matrix = interface.getArpStatsMatrixInfo()
    if not (matrix and host_ip) then return false end
    local req_num = 0;
    local talkers_num = 0;

    for _, m_elem in pairs(matrix) do
        for i, stats in pairs(m_elem)do
            tmp = split(i,"-")
            src_ip = tmp[1]
            dst_ip = tmp[2]

            if  ((stats["src2dst.requests"] > 0) and (src_ip == host_ip)) or
                ((stats["dst2src.requests"] > 0) and (dst_ip == host_ip))then
                
            return true
            end
        end
    end

    return false
end


function addType(t, mac, ip) 
    local typeName = "Unknown"
    local type = 0

    if ip then --first "getHostInfo()". it seems to be more effective
        local hostInfo = interface.getHostInfo(ip)
        if hostInfo then type = hostInfo["devtype"] end
        if type then typeName = discover.devtype2string(type) end
    end

    if typeName == "Unknown" and mac then 
        local macInfo = interface.getMacInfo(mac)
        if macInfo then type = macInfo["devtype"] end
        if type then typeName = discover.devtype2string(type) else typeName = "Unknown" end
    end

    if t[typeName] then
        t[typeName] = t[typeName] + 1
    else
        t[typeName] = 1
    end

    --io.write("["..mac.."] type: "..type..", typename:"..typeName.."; TOT: "..t[typeName].."\n")

    return t
 end


 --funzione che crea, per ogni mac, l'elenco dei talkers ed i loro dispositivi
function arpMatrixModule.getLocalTalkersDeviceType()
    local matrix = interface.getArpStatsMatrixInfo()
    if not matrix then return false end
    local tmp
    local t = {}

    for _, m_elem in pairs(matrix) do
        for i, stats in pairs(m_elem)do
            tmp = split(i,"-")
            src_ip = tmp[1]
            dst_ip = tmp[2]
            src_mac = stats["src_mac"]
            dst_mac = stats["dst_mac"]
    
            if stats["src2dst.requests"] + stats["src2dst.replies"] > 0 then 
                if debug then io.write("src2dst: [ src:"..src_mac.." - dst:"..dst_mac.." ] ENTERING\n") end
                if not t[src_mac] then
                    t[src_mac] = {}
                    t[src_mac].talkersDevices = {}
                    if debug then io.write("src2dst: [ src:"..src_mac.." - dst:"..dst_mac.." ] new elem added\n") end
                end
                t[src_mac].talkersDevices = addType(t[src_mac].talkersDevices, dst_mac, dst_ip ) 
            end
            
            if stats["dst2src.requests"] + stats["dst2src.replies"] > 0 then 
                if debug then io.write("dst2src: [ src:"..src_mac.." - dst:"..dst_mac.." ] ENTERING \n") end
                if not t[dst_mac] then
                    t[dst_mac] = {}
                    t[dst_mac].talkersDevices = {}
                    if debug then io.write("dst2src: [ src:"..src_mac.." - dst:"..dst_mac.." ] new elem added\n") end
                end
                t[dst_mac].talkersDevices = addType(t[dst_mac].talkersDevices, src_mac, src_ip ) 
                if debug then io.write("\n") end
            end
        end
    end
    return t
end

function arpMatrixModule.talkersTot(t)
    if not (t) then return 0 end
    local res = 0

    for i,v in pairs(t) do
        res = res + v
    end
    return res
end

function arpMatrixModule.loadSchemas()
    local schema

    schema = ts_utils.newSchema("host_pair:arp_communication", {step = 300, metrics_type=ts_utils.metrics.gauge})
    schema:addTag("ifid")
    schema:addTag("protocol")
    schema:addTag("id")
    schema:addMetric("num_packets")

    -- ##############################################


    schema = ts_utils.newSchema("mac:local_talkers", {step=300, metrics_type=ts_utils.metrics.gauge} ) 
    schema:addTag("ifid")
    schema:addTag("mac")
    schema:addMetric("num_talkers")

    -- ##############################################

    schema = ts_utils.newSchema("mac:local_talkers_network_devices", {step=300, metrics_type=ts_utils.metrics.gauge} ) 
    schema:addTag("ifid")
    schema:addTag("mac")
    schema:addMetric("num_router_or_switch")
    schema:addMetric("num_wireless_network") 

    -- ##############################################

    schema = ts_utils.newSchema("mac:local_talkers_mobile_devices", {step=300, metrics_type=ts_utils.metrics.gauge} ) 
    schema:addTag("ifid")
    schema:addTag("mac")
    schema:addMetric("num_laptop")
    schema:addMetric("num_tablet") 
    schema:addMetric("num_phone") 

    -- ##############################################

    schema = ts_utils.newSchema("mac:local_talkers_media_devices", {step=300, metrics_type=ts_utils.metrics.gauge} ) 
    schema:addTag("ifid")
    schema:addTag("mac")
    schema:addMetric("num_video")
    schema:addMetric("num_tv")
    schema:addMetric("num_multimedia") 

    -- ##############################################

    schema = ts_utils.newSchema("mac:local_talkers_work_devices", {step=300, metrics_type=ts_utils.metrics.gauge} ) 
    schema:addTag("ifid")
    schema:addTag("mac")
    schema:addMetric("num_computer")
    schema:addMetric("num_printer") 
    schema:addMetric("num_nas") 

    -- ##############################################

    schema = ts_utils.newSchema("mac:local_talkers_iot_devices", {step=300, metrics_type=ts_utils.metrics.gauge} ) 
    schema:addTag("ifid")
    schema:addTag("mac")
    schema:addMetric("num_iot")

    -- ##############################################

    schema = ts_utils.newSchema("mac:local_talkers_unknow_devices", {step=300, metrics_type=ts_utils.metrics.gauge} ) 
    schema:addTag("ifid")
    schema:addTag("mac")
    schema:addMetric("num_unknow")
end

return arpMatrixModule
