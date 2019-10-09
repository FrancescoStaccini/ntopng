--
-- (C) 2013-19 - ntop.org
--

dirs = ntop.getDirs()
package.path = dirs.installdir .. "/scripts/lua/?.lua;" .. package.path
if((dirs.scriptdir ~= nil) and (dirs.scriptdir ~= "")) then package.path = dirs.scriptdir .. "/lua/modules/?.lua;" .. package.path end
require "lua_utils"

--sendHTTPContentTypeHeader('text/html')
sendHTTPContentTypeHeader('Application/json')

local arp_matrix_utils =    require "arp_matrix_utils" 
local discover =            require "discover_utils" 
local net_state = require "nAssistant/network_state"
local json = require("dkjson")

--local matrix = interface.getArpStatsMatrixInfo()




--FUNZIONE TEST
-- le voci della tabella commentate sono legate alla dim temporale
-- si può facilmente modificare per creare stats solo per uno (o predeterminati) host
local function createStats(matrix)

    if not matrix then return nil end

    local t_res = {}
    local t_tmp = {}
    local macInfo = nil
    local hostInfo = nil
    

    for _, m_elem in pairs(matrix) do
        for i,stats in pairs(m_elem)do
            tmp = split(i,"-")
            src_ip = tmp[1]
            dst_ip = tmp[2]

            if not t_res[src_ip] then    --il controllo serve solo per il dst2src

                --ho omesso allcune stats (OS, devType, manufacturer, country)
                --accessibili in tabella nella cella relativa al dst_ip

                macInfo = interface.getMacInfo(stats["src_mac"])
                --hostInfo = interface.getHostInfo(src_ip, nil)

                t_res[src_ip] = {          -- nuovo elemento

                        ip = src_ip,
                        mac = stats["src_mac"],
                        pkts_snt = stats["src2dst.requests"] + stats["src2dst.replies"],
                        pkts_rcvd = stats["dst2src.requests"] + stats["dst2src.replies"],
                        talkers_num = 1,

                        device_type = ternary( macInfo,  discover.devtype2string(macInfo["devtype"]), nil),
                        --TODO: fun di utilità per l'OS
                        OS = ternary(macInfo, macInfo["operatingSystem"], nil ),
                        manufacturer = ternary(macInfo, macInfo["manufacturer"], nil ),

                        talkers = {}
                    }

            else                        -- aggiorno a basta

                t_res[src_ip].pkts_snt = t_res[src_ip].pkts_snt + stats["src2dst.requests"] + stats["src2dst.replies"]
                t_res[src_ip].pkts_rcvd = t_res[src_ip].pkts_rcvd + stats["dst2src.requests"] + stats["dst2src.replies"]
                t_res[src_ip].talkers_num = t_res[src_ip].talkers_num +1
            end

            --ora l'elemento c'è di certo, aggiorno la lista dei talkers
            if not t_res[src_ip].talkers[dst_ip] then --aggiungo talker 
                
                t_res[src_ip].talkers[dst_ip] = { 
                    ip = dst_ip,
                    mac = stats["dst_mac"],
                    pkts_snt = stats["src2dst.requests"] + stats["src2dst.replies"],
                    pkts_rcvd = stats["dst2src.requests"] + stats["dst2src.replies"]

                }
            else        --aggiorno cnt
                t_res[src_ip].talkers[dst_ip].pkts_snt  = t_res[src_ip].talkers[dst_ip].pkts_snt  + stats["src2dst.requests"] + stats["src2dst.replies"]
                t_res[src_ip].talkers[dst_ip].pkts_rcvd = t_res[src_ip].talkers[dst_ip].pkts_rcvd + stats["dst2src.requests"] + stats["dst2src.replies"]
                --potrei controllare se è cambiato il mac (cioè se il dispositivo ha cambiato ip)
            end
--#################################### ############################################################################################################################
                --ORA IL DST2SRC

            if not t_res[dst_ip] then 

                macInfo = ternary( dst_mac ~= "FF:FF:FF:FF:FF:FF", interface.getMacInfo(stats["dst_mac"]), nil )

                t_res[dst_ip] = {          -- nuovo elemento

                        ip = dst_ip,
                        mac = stats["dst_mac"],
                        pkts_rcvd = stats["src2dst.requests"] + stats["src2dst.replies"],
                        pkts_snt = stats["dst2src.requests"] + stats["dst2src.replies"],
                        talkers_num = 1,
                        device_type = ternary( macInfo,  discover.devtype2string(macInfo["devtype"]), nil),
                        OS = ternary(macInfo, macInfo["operatingSystem"], nil ),--TODO: fun di utilità per l'OS
                        manufacturer = ternary(macInfo, macInfo["manufacturer"], nil ),

                        talkers = {}
                    }

            else                        -- aggiorno a basta

                t_res[dst_ip].pkts_snt = t_res[dst_ip].pkts_snt + stats["dst2src.requests"] + stats["dst2src.replies"]
                t_res[dst_ip].pkts_rcvd = t_res[dst_ip].pkts_rcvd +  stats["src2dst.requests"] + stats["src2dst.replies"]
                t_res[dst_ip].talkers_num = t_res[dst_ip].talkers_num +1
            end

            --ora l'elemento c'è di certo, aggiorno la lista dei talkers
            if not t_res[dst_ip].talkers[src_ip] then --aggiungo talker 
                
                t_res[dst_ip].talkers[src_ip] = { 
                    ip = src_ip,
                    mac = stats["dst_mac"],
                    pkts_rcvd = stats["src2dst.requests"] + stats["src2dst.replies"],
                    pkts_snt = stats["dst2src.requests"] + stats["dst2src.replies"]

                }
            else        --aggiorno cnt
                t_res[dst_ip].talkers[src_ip].pkts_snt  = t_res[dst_ip].talkers[src_ip].pkts_snt  + stats["dst2src.requests"] + stats["dst2src.replies"]
                t_res[dst_ip].talkers[src_ip].pkts_rcvd = t_res[dst_ip].talkers[src_ip].pkts_rcvd + stats["src2dst.requests"] + stats["src2dst.replies"]
                --potrei controllare se è cambiato il mac (cioè se il dispositivo ha cambiato ip)
            end



        end
    end
    --here i can elaborate the ratio stats

    return t_res
end


--print(json.encode( interface.getIfNames() ))
--[[
    {"1":"enp3s0","2":"lo"}
]]
--print( tostring(ifname) )
--print( json.encode(createStats(matrix), {indent = true} ) )
--print( json.encode( interface.findHost("bucci-PC"), {indent = true} ) )
--print( json.encode( table.len(interface.findHost("pc")), {indent = true} ) )

--print( json.encode( interface.getnDPIProtocols(), {indent = true} ) )

-- local params = {}
-- --params = {"bytes.sent", "ip", "ipkey", "names.dhcp" }
-- params = {"name"}
-- local res = {}
-- net_state.get_stats( "localhost", params, 2, res)
-- print(  json.encode( res, {indent = true})  )

--print(  json.encode( interface.getActiveFlowsStats(), {indent = true})  )

--function network_state.get_stats( type, res, params, caller_deadline,  caller_callback) FIRMA
-- local res = {}
-- net_state.get_stats("flow", res)
-- print(  json.encode( res, {indent = true})  )

-- local res = {}
-- local category = "Web"
-- local function mycall(name, stats)
--     if stats["ndpi_categories"] and stats["ndpi_categories"][category] and stats["ndpi_categories"][category]["bytes"]then 
--         res[name] = stats["ndpi_categories"][category]["bytes"]
--         --tprint(stats.ndpi_categories.Web.bytes)
--     end

--     --tprint(stats.ndpi_categories)

--     return 
-- end
  
-- net_state.get_stats("devices", nil, nil, nil, mycall)
-- print(  json.encode( res, {indent = true}) )

--print(  json.encode(  interface.getMacInfo(" 30:10:B3:0A:33:AB" ), {indent = true}) )
--print(  json.encode( interface.getHostInfo("fe80::c004:401e:a787:6f0c"), {indent = true}) )


-- local a="a"
-- print(  json.encode( string.len("ntopng.prefs.ndpi_flows_rrd_creation"), {indent = true}) )


--======================================================================================
--++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
--MISBEHAVING FLOW: Ntopng can detect possibly anomalous flows, and report them as alerts.
--                  Such flows are called “Misbehaving Flows”.
--++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
--======================================================================================
require "alert_utils"
local dialogflow = require "nAssistant/dialogflow_APIv2"
local net_state = require "nAssistant/network_state"
local df_utils = require "nAssistant/dialogflow_utils" --NOTE: poi andranno nelle utils
local flow_consts = require "flow_consts"

-- local s = {}
-- for i = 0, 27, 1 do 
--     s[i] = flow_consts.flow_status_types[i].i18n_title
--     s[i] = string.gsub(s[i], "_", " ")
--     s[i] = string.gsub(s[i], "flow_details.", "") 
--     s[i] = string.gsub(s[i], "alerts_dashboard.", "") 
--     s[i] = s[i].."\""
-- end 

-- tprint(s)

--print( json.encode( interface.findFlowByKey(688828559), {indent = true}) )

local query = "bri" 
local res = {}

print( json.encode( interface.findHost(query), {indent = true}) )
-- local ip_to_name = ntop.getHashAllCache(getHostAltNamesKey()) or {}

-- for ip,name in pairs(ip_to_name) do
--   if string.contains(string.lower(name), string.lower(query)) then
--       res[ip] = hostVisualization(ip, name)     --note: hostVisualization(...) mette "[IPv6]"agli host con ip v6
--   end
-- end

local mac_to_name = ntop.getHashAllCache(getDhcpNamesKey(getInterfaceId(ifname))) or {}
for mac, name in pairs(mac_to_name) do
   if string.contains(string.lower(name), string.lower(query)) then
      res[mac] = hostVisualization(mac, name)
   end
end

 print( json.encode( res, {indent = true}) )
 print( json.encode( interface.findHostByMac("00:1F:CF:61:19:64"), {indent = true}) )

-- local a= {aaa = "bbb"}





    --tprint("MISBEHAVING:")
    --tprint(mis_flows[1].status)
    --[[esempio di un elemendo di mis_flows:
          1 table
          1.status table
          1.tot_flows_bytes number 255188
          1.addr string 192.168.1.212
          1.flow_counter number 0
  
    ]]
 
  --print( json.encode( interface.getHostInfo( getHostAltName("00:1F:CF:61:19:64") ) ), {indent = true} ) 

--QUESTA È UTILE
--print( json.encode( interface.getEngagedAlertsCount(0), {indent = true}) )

-- firma: function getAlerts(what, options, with_counters) 
--      what --> "engaged"/"release"
--        options --> ??????????



--local res = net_state.get_hosts_flow_misbehaving_stats()
--print( json.encode( res ), {indent = true} ) 


--print( json.encode(interface.getStats() ), {indent = true} ) 
-----------------------------------------------------------------------------
--STATS DI "2019-06-22-traffic-analysis-exercise.pcap"

    --in show_alert
    --23 FLOW ALERT, che aggregano i 69 flow alerted

    --in flow_stats:
        --346 flow con misbehaving status (filtro "all misbehaving")
        --69 alerted flow (filtro all alerted)
-----------------------------------------------------------------------------


--[[
esempio alert_flow potenzialmente pericoloso:	
    cli_localhost	"0"
    alert_tstamp	"1568909450"
    cli_os	""
    alert_json	"{ \"info\": \"syndication.twitter.com\", \"status_info\": { \"cli.devtype\": 0, \"srv.devtype\": 8, \"ntopng.key\": 1928694160, \"ja3_signature\": \"4d7a28d6f2263ed61de88ca66eb011e3\" } }"
    l7_proto	"120"
    srv_asn	"0"
    flow_status	"27"
    cli2srv_bytes	"3540"
    alert_severity	"1"
    cli_asn	"0"
    l7_master_proto	"91"
    srv_localhost	"0"
    rowid	"1"
    cli_blacklisted	"0"
    cli2srv_packets	"26"
    srv2cli_bytes	"10344"
    vlan_id	"0"
    srv2cli_packets	"23"
    srv_country	""
    alert_type	"48"
    cli_country	""
    cli_addr	"10.0.76.193"
    srv_addr	"104.244.42.8"
    srv_os	""
    alert_counter	"2"
    alert_tstamp_end	"1568909450"
    srv_blacklisted	"0"
    proto	"6"


esempio flow normale
    ntopng.key	2695364967
    goodput_bytes	0
    srv.key	3758096386
    flow.status	0
    bytes	46
    srv.ip	"224.0.0.2"
    cli.ip	"192.168.1.99"
    srv.port	0
    status_map	1
    flow.idle	false
    cli.key	3232235875
    cli.port	0
]]



--1 interface.getStats() --> DALLA IF POSSO PRENDERE GLI ENGAGED ALERTS, DROPPED ALERTS, E HAS ALERT

--======================================================================================
--++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
--======================================================================================



--print(  json.encode( ntop.getPref("ntopng.prefs.ndpi_flows_rrd_creation"), {indent = true}) )

--print(  json.encode( interface.getStats(), {indent = true})  )
--print(  json.encode( net_state.get_ndpi_proto_traffic_volume(), {indent = true})  )
--print(  json.encode( net_state.check_top_application_protocol(), {indent = true})  )

--tprint(t)
--print( json.encode( t, {indent = true}) )
--tprint(interface.getMacInfo("00:00:5E:00:01:61" ) )

-- local macs = interface.getMacsInfo().macs
-- for i,v in pairs(macs)do print(v.mac..";") end

--print( json.encode( interface.getMacsInfo(), {indent = true}) )
--print( json.encode( interface.getMacInfo("AC:9E:17:81:A1:76" ), {indent = true}) )
--print( json.encode( getHostAltName("D8:18:D3:78:CB:2F"), {indent = true}) ) 
--print( json.encode( interface.findHost("FRA"), {indent = true}) )
--print( json.encode( interface.getMacDeviceTypes(), {indent = true}) )
--print( json.encode( arp_matrix_utils.getLocalTalkersDeviceType(), {indent = true} ) )

--test tocheck dropbox namespaces
--local dropbox = require "dropbox_utils"
-- tprint(  dropbox.getNamespaces() )
--print( json.encode(  dropbox.getNamespaces(), {indent = true}) )

--local mac = "AC:9E:17:81:A1:76"
--print( json.encode( interface.findHostByMac(mac) , {indent = true}) )


--++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
--++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++


--[[ MAC INFO

    source_mac boolean true
    throughput_trend_bps number 2
    operatingSystem number 0
    bytes.ndpi.unknown number 0
    bytes.rcvd.anomaly_index number 0
    arp_replies.rcvd number 0
    seen.last number 1556543236
    bytes.rcvd number 0
    packets.sent.anomaly_index number 100
    throughput_trend_bps_diff number -12.012893676758
    manufacturer string Dell Inc.
    bridge_seen_iface_id number 0
    pool number 0
    throughput_trend_pps number 2
    bytes.sent number 3840
    arp_requests.rcvd number 0
    special_mac boolean false
    location string unknown
    throughput_pps number 0.59977388381958
    duration number 375
    packets.rcvd.anomaly_index number 0
    seen.first number 1556542862
    num_hosts number 0
    devtype number 0
    packets.rcvd number 0
    packets.sent number 64
    arp_requests.sent number 64
    last_throughput_pps number 0.79998880624771
    arp_replies.sent number 0
    last_throughput_bps number 47.999328613281
    throughput_bps number 35.986434936523
    bytes.sent.anomaly_index number 100
    fingerprint string 
    mac string 14:18:77:53:49:9C

        per la stringa relativa al tipo
        discover.devtype2string(num_type)
]]


--[[ HOST INFO

    bytes.ndpi.unknown number 0
    tcp.packets.lost number 0
    active_flows.as_server number 0
    systemhost boolean false
    udp.bytes.sent number 29669
    json string { "flows.as_client": 5, "flows.as_server": 0, "anomalous_flows.as_client": 0, "anomalous_flows.as_server": 0, "unreachable_flows.as_client": 0, "unreachable_flows.as_server": 0, "host_unreachable_flows.as_client": 0, "host_unreachable_flows.as_server": 0, "total_alerts": 0, "sent": { "packets": 52, "bytes": 29669 }, "rcvd": { "packets": 0, "bytes": 0 }, "ndpiStats": { "MDNS": { "duration": 20, "bytes": { "sent": 25801, "rcvd": 0 }, "packets": { "sent": 32, "rcvd": 0 } }, "NetBIOS": { "duration": 15, "bytes": { "sent": 2360, "rcvd": 0 }, "packets": { "sent": 16, "rcvd": 0 } }, "Dropbox": { "duration": 5, "bytes": { "sent": 1508, "rcvd": 0 }, "packets": { "sent": 4, "rcvd": 0 } }, "categories": { "Cloud": { "id": 13, "bytes_sent": 1508, "bytes_rcvd": 0, "duration": 5 }, "Network": { "id": 14, "bytes_sent": 25801, "bytes_rcvd": 0, "duration": 20 }, "System": { "id": 18, "bytes_sent": 2360, "bytes_rcvd": 0, "duration": 15 } } }, "total_activity_time": 25, "ip": { "ipVersion": 4, "localHost": false, "ip": "146.48.99.68" }, "mac_address": "00:0E:C6:C7:D8:4A", "ifid": 3, "seen.first": 1556542967, "seen.last": 1556542989, "last_stats_reset": 0, "asn": 137, "symbolic_name": "Marlin", "asname": "Consortium GARR", "localHost": false, "systemHost": false, "broadcastDomainHost": true, "is_blacklisted": false, "num_alerts": 0 }
    continent string EU
    os string 
    low_goodput_flows.as_server number 0
    packets.sent number 52
    bytes.rcvd number 0
    total_alerts number 0
    host_pool_id number 0
    tcp.bytes.sent.anomaly_index number 0
    privatehost boolean false
    ipkey number 2452644676
    is_multicast boolean false
    longitude number 12.109700202942
    bytes.rcvd.anomaly_index number 0
    tcp.packets.out_of_order number 0
    drop_all_host_traffic boolean false
    packets.rcvd number 0
    dhcpHost boolean false
    duration number 23
    tcp.packets.rcvd number 0
    throughput_pps number 0.0
    other_ip.bytes.rcvd.anomaly_index number 0
    broadcast_domain_host boolean true
    tskey string 146.48.99.68
    other_ip.packets.sent number 0
    udp.bytes.sent.anomaly_index number 0
    low_goodput_flows.as_client.anomaly_index number 0
    seen.first number 1556542967
    total_activity_time number 25
    throughput_trend_pps number 2
    tcp.packets.sent number 0
    is_broadcast boolean false
    tcp.packets.retransmissions number 0
    anomalous_flows.as_server number 0
    low_goodput_flows.as_client number 0
    packets.sent.anomaly_index number 0
    host_unreachable_flows.as_client number 0
    icmp.bytes.rcvd.anomaly_index number 0
    latitude number 43.147899627686
    country string IT
    last_throughput_pps number 0.80018645524979
    throughput_trend_bps number 2
    names table
    names.dhcp string Marlin
    names.mdns string Marlin
    num_alerts number 0
    ifid number 3
    name string Marlin
    asname string Consortium GARR
    udp.bytes.rcvd.anomaly_index number 0
    udp.packets.rcvd number 0
    active_http_hosts number 0
    other_ip.bytes.rcvd number 0
    other_ip.packets.rcvd number 0
    contacts.as_client number 0
    other_ip.bytes.sent.anomaly_index number 0
    ndpi table
    ndpi.Dropbox table
    ndpi.Dropbox.packets.rcvd number 0
    ndpi.Dropbox.duration number 5
    ndpi.Dropbox.packets.sent number 4
    ndpi.Dropbox.bytes.rcvd number 0
    ndpi.Dropbox.breed string Acceptable
    ndpi.Dropbox.bytes.sent number 1508
    ndpi.MDNS table
    ndpi.MDNS.packets.rcvd number 0
    ndpi.MDNS.duration number 20
    ndpi.MDNS.packets.sent number 32
    ndpi.MDNS.bytes.rcvd number 0
    ndpi.MDNS.breed string Acceptable
    ndpi.MDNS.bytes.sent number 25801
    ndpi.NetBIOS table
    ndpi.NetBIOS.packets.rcvd number 0
    ndpi.NetBIOS.duration number 15
    ndpi.NetBIOS.packets.sent number 16
    ndpi.NetBIOS.bytes.rcvd number 0
    ndpi.NetBIOS.breed string Acceptable
    ndpi.NetBIOS.bytes.sent number 2360
    icmp.packets.sent number 0
    asn number 137
    packets.rcvd.anomaly_index number 0
    flows.as_server number 0
    icmp.bytes.sent number 0
    ip string 146.48.99.68
    bytes.sent.anomaly_index number 0
    udp.bytes.rcvd number 0
    udp.packets.sent number 52
    mac string 00:0E:C6:C7:D8:4A
    tcp.bytes.rcvd number 0
    vlan number 0
    flows.as_client number 5
    tcp.bytes.sent number 0
    devtype number 4
    low_goodput_flows.as_server.anomaly_index number 0
    contacts.as_server number 0
    throughput_trend_bps_diff number -301.67028808594
    localhost boolean false
    active_flows.as_client number 5
    other_ip.bytes.sent number 0
    childSafe boolean false
    unreachable_flows.as_server number 0
    unreachable_flows.as_client number 0
    seen.last number 1556542989
    tcp.bytes.rcvd.anomaly_index number 0
    ndpi_categories table
    ndpi_categories.System table
    ndpi_categories.System.bytes.sent number 2360
    ndpi_categories.System.duration number 15
    ndpi_categories.System.category number 18
    ndpi_categories.System.bytes.rcvd number 0
    ndpi_categories.System.bytes number 2360
    ndpi_categories.Network table
    ndpi_categories.Network.bytes.sent number 25801
    ndpi_categories.Network.duration number 20
    ndpi_categories.Network.category number 14
    ndpi_categories.Network.bytes.rcvd number 0
    ndpi_categories.Network.bytes number 25801
    ndpi_categories.Cloud table
    ndpi_categories.Cloud.bytes.sent number 1508
    ndpi_categories.Cloud.duration number 5
    ndpi_categories.Cloud.category number 13
    ndpi_categories.Cloud.bytes.rcvd number 0
    ndpi_categories.Cloud.bytes number 1508
    icmp.bytes.sent.anomaly_index number 0
    total_flows.as_client number 5
    tcp.packets.keep_alive number 0
    icmp.bytes.rcvd number 0
    total_flows.as_server number 0
    pktStats.sent table
    pktStats.sent.upTo1024 number 2
    pktStats.sent.rst number 0
    pktStats.sent.finack number 0
    pktStats.sent.upTo1518 number 14
    pktStats.sent.above9000 number 0
    pktStats.sent.upTo512 number 10
    pktStats.sent.synack number 0
    pktStats.sent.syn number 0
    pktStats.sent.upTo64 number 0
    pktStats.sent.upTo2500 number 0
    pktStats.sent.upTo9000 number 0
    pktStats.sent.upTo6500 number 0
    pktStats.sent.upTo128 number 10
    pktStats.sent.upTo256 number 16
    icmp.packets.rcvd number 0
    pktStats.recv table
    pktStats.recv.upTo1024 number 0
    pktStats.recv.rst number 0
    pktStats.recv.finack number 0
    pktStats.recv.upTo1518 number 0
    pktStats.recv.above9000 number 0
    pktStats.recv.upTo512 number 0
    pktStats.recv.synack number 0
    pktStats.recv.syn number 0
    pktStats.recv.upTo64 number 0
    pktStats.recv.upTo2500 number 0
    pktStats.recv.upTo9000 number 0
    pktStats.recv.upTo6500 number 0
    pktStats.recv.upTo128 number 0
    pktStats.recv.upTo256 number 0
    operatingSystem number 0
    city string 
    anomalous_flows.as_client number 0
    is_blacklisted boolean false
    has_dropbox_shares boolean true
    bytes.sent number 29669
    host_unreachable_flows.as_server number 0
    hiddenFromTop boolean false
    tcp.packets.seq_problems boolean false
    last_throughput_bps number 301.67028808594
    throughput_bps number 0.0






    macs.1.throughput_trend_bps_diff number 0.0
    macs.1.bytes.sent number 6030
    macs.1.location string lan
    macs.1.arp_requests.rcvd number 0
    macs.1.arp_replies.rcvd number 0
    macs.1.bytes.sent.anomaly_index number 60
    macs.1.packets.rcvd.anomaly_index number 0
    macs.1.throughput_pps number 0.0
    macs.1.fingerprint string 
    macs.1.throughput_bps number 0.0
    macs.1.seen.last number 1557827812
    macs.1.talkers.asServer number 0
    macs.1.talkers.asClient number 6
    macs.1.packets.sent.anomaly_index number 0
    macs.1.source_mac boolean true
    macs.1.duration number 341
    macs.1.special_mac boolean false
    macs.1.last_throughput_bps number 0.0
    macs.1.seen.first number 1557827472
    macs.1.arp_requests.sent number 107
    macs.1.pool number 0
    macs.1.bytes.rcvd number 0
    macs.1.devtype number 0



    DEVICE TABLE(quella passata a ts_utils_append(...))

    table
    arp_requests.sent number 0
    bytes.rcvd number 942695
    bytes.sent number 0
    mac string FF:FF:FF:FF:FF:FF
    pool number 0
    devtype number 0
    arp_replies.rcvd number 10
    packets.sent.anomaly_index number 0
    throughput_pps number 80.430160522461
    packets.rcvd number 12861
    throughput_bps number 7064.2490234375
    bridge_seen_iface_id number 0
    bytes.rcvd.anomaly_index number 100
    location string unknown
    last_throughput_bps number 6710.5068359375
    source_mac boolean false
    arp_replies.sent number 0
    seen.first number 1558082557
    special_mac boolean true
    arp_requests.rcvd number 11999
    talkers.asServer number 1557
    talkers.asClient number 3
    bytes.sent.anomaly_index number 0
    throughput_trend_bps number 1
    num_hosts number 2
    throughput_trend_bps_diff number 353.7421875
    fingerprint string 
    bytes.ndpi.unknown number 0
    operatingSystem number 0
    packets.sent number 0
    duration number 1
    packets.rcvd.anomaly_index number 100
    seen.last number 1558082557
    last_throughput_pps number 95.141967773438
    throughput_trend_pps number 2



]]
