--
-- (C) 2013-19 - ntop.org
--

local dirs = ntop.getDirs()
package.path = dirs.installdir .. "/scripts/lua/modules/?.lua;" .. package.path
require "lua_utils"


local arpMatrixModule = {}

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

function arpMatrixModule.getLocalTalkersDeviceType()
    local matrix = interface.getArpStatsMatrixInfo()
    if not matrix then return false end

    local t = {}

    if (matrix and host_ip)  then 

        for _, m_elem in pairs(matrix) do
            for i, stats in pairs(m_elem)do
                tmp = split(i,"-")
                src_ip = tmp[1]
                dst_ip = tmp[2]

                
                    
                
                end
            end
        end

    end


    return t
    
    
end

return arpMatrixModule
