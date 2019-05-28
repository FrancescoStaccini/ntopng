--
-- (C) 2013-19 - ntop.org
--

local dirs = ntop.getDirs()
package.path = dirs.installdir .. "/scripts/lua/modules/?.lua;" .. package.path
require "lua_utils"
local discover = require "discover_utils"

local arpMatrixModule = {}
local debug = false

--WIP
--TODO & TEST: callback/iterator for the matrix
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

--  function addType(t,addr) --t è la tabella t[mac].talkersDevices
--     local typeName = "Unknown"
--     local type = 0
--     --NOTE: this is for the "mac_ts" version------------------------------------------------
--     -- local macInfo = interface.getMacInfo(addr)
--     -- if macInfo then type = macInfo["devtype"] end
--     -- if type then typeName = discover.devtype2string(type) else typeName = "Unknown" end
--     -------------------------------------------------------------------------------------
--     local hostInfo = interface.getHostInfo(addr, nil)
--     if hostInfo then
--         type = hostInfo["devtype"]
--         io.write("addType - host: "..addr.." OK \n")
--     else 
--         io.write("addType - host: "..addr.." got nil \n")
--     end
--     if type then typeName = discover.devtype2string(type) end

--     if t[typeName] then
--         t[typeName] = t[typeName] + 1
--     else
--         t[typeName] = 1
--     end
--     --io.write("addr: "..addr.." type: "..type..", typename:"..typeName.."; TOT: "..t[typeName].."\n")

--     return t
--  end

--  --NOTE & TODO: come faccio a capire se il talker è server o client? 
--  --             nella matrice src e dst sono fittizi, vengono decisi in base ad una comparazione di bit

--  --funzione che crea, per ogni mac, l'elenco dei talkers ed i loro dispositivi
-- function arpMatrixModule.getLocalTalkersDeviceType()
--     local matrix = interface.getArpStatsMatrixInfo()
--     if not matrix then return false end
--     local tmp
--     local t = {}

--     for _, m_elem in pairs(matrix) do
--         for i, stats in pairs(m_elem)do
--             tmp = split(i,"-")
--             src_ip = tmp[1]
--             dst_ip = tmp[2]
--             src_mac = stats["src_mac"]
--             dst_mac = stats["dst_mac"]
    
--             if stats["src2dst.requests"] + stats["src2dst.replies"] > 0 then 
--                 if debug then io.write("src2dst: [ src:"..src_mac.." - dst:"..dst_mac.." ] ENTERING\n") end
--                 if not t[src_ip] then
--                     t[src_ip] = {}
--                     t[src_ip].talkersDevices = {}
--                     -- t[src_mac].talkersAsClient = 0
--                     -- t[src_mac].talkersAsServer = 0
--                     if debug then io.write("src2dst: [ src:"..src_mac.." - dst:"..dst_mac.." ] new elem added\n") end
--                 end
--                 t[src_ip].talkersDevices = addType(t[src_ip].talkersDevices, dst_ip ) 
--             end
            
--             if stats["dst2src.requests"] + stats["dst2src.replies"] > 0 then 
--                 if debug then io.write("dst2src: [ src:"..src_mac.." - dst:"..dst_mac.." ] ENTERING \n") end
--                 if not t[dst_ip] then
--                     t[dst_ip] = {}
--                     t[dst_ip].talkersDevices = {}
--                     -- t[dst_mac].talkersAsClient = 0
--                     -- t[dst_mac].talkersAsServer = 0
--                     if debug then io.write("dst2src: [ src:"..src_mac.." - dst:"..dst_mac.." ] new elem added\n") end
--                 end
--                 t[dst_ip].talkersDevices = addType(t[dst_ip].talkersDevices, src_ip ) 
--                 if debug then io.write("\n") end
--             end
--         end
--     end
--     return t
-- end


function addType(t,addr) --t è la tabella t[mac].talkersDevices
    local typeName = "Unknown"
    local type = 0
    --NOTE: this is for the "mac_ts" version
    local macInfo = interface.getMacInfo(addr)
    if macInfo then type = macInfo["devtype"] end
    if type then typeName = discover.devtype2string(type) else typeName = "Unknown" end

    --NOTE: for host version
    -- local hostInfo = interface.getHostInfo(addr, nil)
    -- tprint(hostInfo)
    -- if hostInfo then type = hostInfo["devtype"] end
    -- if type then typeName =  discover.devtype2string(type) end

    if t[typeName] then
        t[typeName] = t[typeName] + 1
    else
        t[typeName] = 1
    end

    --io.write("["..addr.."] type: "..type..", typename:"..typeName.."; TOT: "..t[typeName].."\n")

    return t
 end

 --NOTE & TODO: come faccio a capire se il talker è server o client? 
 --             nella matrice src e dst sono fittizi, vengono decisi in base ad una comparazione di bit

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
                    -- t[src_mac].talkersAsClient = 0
                    -- t[src_mac].talkersAsServer = 0
                    if debug then io.write("src2dst: [ src:"..src_mac.." - dst:"..dst_mac.." ] new elem added\n") end
                end
                t[src_mac].talkersDevices = addType(t[src_mac].talkersDevices, dst_mac ) 
            end
            
            if stats["dst2src.requests"] + stats["dst2src.replies"] > 0 then 
                if debug then io.write("dst2src: [ src:"..src_mac.." - dst:"..dst_mac.." ] ENTERING \n") end
                if not t[dst_mac] then
                    t[dst_mac] = {}
                    t[dst_mac].talkersDevices = {}
                    -- t[dst_mac].talkersAsClient = 0
                    -- t[dst_mac].talkersAsServer = 0
                    if debug then io.write("dst2src: [ src:"..src_mac.." - dst:"..dst_mac.." ] new elem added\n") end
                end
                t[dst_mac].talkersDevices = addType(t[dst_mac].talkersDevices, src_mac ) 
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

return arpMatrixModule

--[[
    arp-matrix element example:

    {
    "146.48.56.1-146.48.57.247":{
      "src_mac":"B4:0C:25:E0:40:4C",
      "src2dst.requests":0,
      "dst2src.replies":0,
      "dst2src.requests":0,
      "src2dst.replies":1,
      "dst_mac":"B4:0C:25:E0:40:4C"
    }



    roba:

                        -- t[src_mac] = {
                    --     unknown = 0,
                    --     printer = 0,
                    --     video = 0,
                    --     workstation = 0,
                    --     laptop = 0,
                    --     tablet = 0,
                    --     phone = 0,
                    --     tv = 0,
                    --     networking = 0,
                    --     wifi = 0,
                    --     nas = 0,
                    --     multimedia = 0,
                    --     iot = 0,
                    -- }

]]
