--
-- (C) 2019 - ntop.org
--

local flow_consts = require("flow_consts")
local user_scripts = require("user_scripts")

-- #################################################################

local script = {
  -- NOTE: hooks defined below
  hooks = {},

  gui = {
    i18n_title = "flow_callbacks_config.web_mining",
    i18n_description = "flow_callbacks_config.web_mining_description",
  }
}

-- #################################################################

function script.hooks.protocolDetected(now)
  if(flow.getnDPICategoryName() == "Mining") then
    flow.triggerStatus(flow_consts.status_types.status_web_mining_detected.status_id)
  end
end

-- #################################################################

return script
