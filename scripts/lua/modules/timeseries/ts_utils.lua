--
-- (C) 2018 - ntop.org
--

local ts_utils = require("ts_utils_core")

-- Include the schemas
ts_utils.loadSchemas()


--WIP
if ntop.getPref("ntopng.prefs.is_arp_matrix_generation_enabled") then 
    local am_utils = require "arp_matrix_utils" 
    am_utils.loadSchemas()
end

return ts_utils
