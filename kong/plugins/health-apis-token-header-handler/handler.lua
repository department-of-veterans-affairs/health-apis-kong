--
-- This plugin will be used to facilitate the use of static tokens that allow
-- access to certain parts of an application (e.g. raw requests, bulk fhir).
--
-- To do this, the plugin takes a header name (e.g. raw) and a list of token values.
-- This list of values allows for easy creation and revocation of tokens when necessary.
-- For ease of use, the header passed to the application will be a boolean string
-- The header will become true if the token provided is valid and false if not.
-- This header value will match the request header value unless an application header
-- value is provided in its configuration.
--

local HealthApisTokenHeaderHandler = require("kong.plugins.base_plugin"):extend()

function HealthApisTokenHeaderHandler:new()
  HealthApisTokenHeaderHandler.super.new(self, "health-apis-token-headers")
end

--
-- When client hits service
--
function HealthApisTokenHeaderHandler:access()
  HealthApisTokenHeaderHandler.super.access(self)

  local tokenHeaderKey = self.conf.request_header_key
  local tokenHeaderValue = ngx.req.get_headers()[tokenHeaderKey]

--
-- If request doesnt contain header, skip
--
  if (tokenHeaderValue == nil) then
    return
  end

--
-- The good stuff:
-- Determine if the value of the header is in the allowed token values
--

-- If a separate header value is provided for the application then we will use that
-- otherwise, we'll just set the already existing header value to be a boolean.
  if (self.conf.application_header_key != nil) then
    local appHeader = self.conf.application_header_key
  else
    local appHeader = tokenHeaderKey
  end

  kong.service.request.set_header(appHeader, "false")

  for i,token in ipairs(self.conf.allowed_tokens) do
    if (token == tokenHeaderValue) then
      kong.log.info("Request Header (" .. tokenHeaderKey .. ") has valid token.")
      kong.service.request.set_header(appHeader, "true")
      break
    end
  end

-- end of HealthApisTokenHeaderHandler:access()
end

-- end of HealthApisTokenHeaderHandler plugin
return HealthApisTokenHeaderHandler;
