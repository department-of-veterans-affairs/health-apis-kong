local HealthApisPatientRegistration = require("kong.plugins.base_plugin"):extend()

function HealthApisPatientRegistration:new()
  HealthApisPatientRegistration.super.new(self, "health-apis-static-token-handler")
end

function HealthApisPatientRegistration:access(conf)
  HealthApisPatientRegistration.super.access(self)

  self.conf = conf

  if (self.conf.ids_url == nil) then
    ngx.log(ngx.ERR, "IDS URL not set.")
    return
  end

  -- Required by lua (request body data not loaded by default)
  ngx.req.read_body()

  local body, errors = ngx.req.get_post_args()

  if errors == "truncated" then
    -- one can choose to ignore or reject the current request here
  end

  if not body then
    ngx.log(ngx.ERR, "failed to get post args: ", errors)
    return
  end

  --Retrieve ICN
  --Register with IDS

end


-- Format and send the response to the client
function HealthApisPatientRegistration:send_response(status_code, message)

  ngx.status = status_code
  ngx.header["Content-Type"] = "application/json"
  ngx.say(message)
  ngx.exit(status_code)
  
end


HealthApisPatientRegistration.PRIORITY = 1010

return HealthApisPatientRegistration
