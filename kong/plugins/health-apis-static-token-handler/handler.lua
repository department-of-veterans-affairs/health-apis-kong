local HealthApisStaticTokenHandler = require("kong.plugins.base_plugin"):extend()

function HealthApisStaticTokenHandler:new()
  HealthApisStaticTokenHandler.super.new(self, "health-apis-static-token-handler")
end

function HealthApisStaticTokenHandler:access(conf)
  HealthApisStaticTokenHandler.super.access(self)
  kong.log.info("Checking for static access token.")

  self.conf = conf

  if (self.conf.static_refresh_token == nil) then
    kong.log.info("Static refresh token not specified")
    return
  end

  -- Required by lua (request body data not loaded by default)
  ngx.req.read_body()

  local body, errors = ngx.req.get_post_args()

  if not body then
    ngx.log(ngx.ERR, "Failed to get post args: ", errors)
    return
  end

  local requestRefreshToken = body["refresh_token"]

  if (requestRefreshToken == self.conf.static_refresh_token) then
    ngx.log(ngx.INFO, "Static refresh token requested")
    self:return_static_token()
  end
  kong.log.info("Static Access Complete")
end

function HealthApisStaticTokenHandler:return_static_token()
  kong.log.info("Returning static token")
  local staticTokenResponse = '{\n' ..
    '    "access_token": "' .. self.conf.static_access_token .. '",\n' ..
    '    "expires_in": ' .. self.conf.static_expiration .. ',\n' ..
    '    "token_type": "bearer",\n' ..
    '    "refresh_token": "' .. self.conf.static_refresh_token .. '",\n' ..
    '    "scope": "' .. self.conf.static_scopes .. '",\n' ..
    '    "patient": "' .. self.conf.static_icn .. '"\n' ..
    '}'
  
  self:send_response(200, staticTokenResponse)

end

-- Format and send the response to the client
function HealthApisStaticTokenHandler:send_response(status_code, message)

  ngx.status = status_code
  ngx.header["Content-Type"] = "application/json"
  ngx.say(message)
  ngx.exit(status_code)

end


HealthApisStaticTokenHandler.PRIORITY = 1010

return HealthApisStaticTokenHandler
