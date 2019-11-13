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
    i18n_title = "flow_callbacks_config.remote_to_remote",
    i18n_description = "flow_callbacks_config.remote_to_remote_description",
    input_builder = user_scripts.flow_checkbox_input_builder,
  }
}

-- #################################################################

function script.hooks.protocolDetected(now)
  if(flow.isRemoteToRemote() and flow.isUnicast()) then
    flow.triggerStatus(flow_consts.status_types.status_remote_to_remote.status_id)
  end
end

-- #################################################################

return script
