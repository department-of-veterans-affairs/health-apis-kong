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
local HealthApisTokenProtectedOperation = require("kong.plugins.base_plugin"):extend()

function HealthApisTokenProtectedOperation:new()
  HealthApisTokenProtectedOperation.super.new(self, "health-apis-token-headers")
end

--
-- When client hits service
--
function HealthApisTokenProtectedOperation:access(conf)
  HealthApisTokenProtectedOperation.super.access(self)

  self.conf = conf

  tokenHeaderKey = self.conf.request_header_key
  tokenHeaderValue = ngx.req.get_headers()[tokenHeaderKey]

  -- If request doesnt contain header, skip
  if (tokenHeaderValue == nil) then
    return
  end

--
-- The good stuff:
-- Determine if the value of the header is in the allowed token values
--

  kong.log.info("Validating Token Received Under Header: " .. tokenHeaderKey)

  -- Invalid Until Proven Valid
  isValidToken = false
  self:validateToken()

  -- Set the boolean header if one was given in the configuration
  if (self.conf.send_boolean_header ~= nil) then
    kong.service.request.set_header(self.conf.send_boolean_header, isValidToken)
  end

  -- If we get here, we checked a token. Let's make sure we perform necessary
  -- actions if its invalid.
  self:takeActionForInvalidToken()

-- end of HealthApisTokenProtectedOperation:access()
end

--
-- Validates the token against a list of allowed_tokens provided in the
-- plugins configration
--
function HealthApisTokenProtectedOperation:validateToken()
  for i,token in ipairs(self.conf.allowed_tokens) do
    if (token == tokenHeaderValue) then
      kong.log.info("Header:[" .. tokenHeaderKey .. "] has valid token.")
      isValidToken = true
      break
    end
  end

-- end of HealthApisTokenProtectedOperation:validateToken()
end

--
-- Determines if a token is invalid and, if so, what action to take.
-- If the sends_unauthorized configuration is set, sends a 401
-- Else falls through to the default method (ex. raw falls through to a
-- plain-jane data-query request instead of the raw response)
--
function HealthApisTokenProtectedOperation:takeActionForInvalidToken()
  if (isValidToken == false) then
    kong.log.info("Header:[" .. tokenHeaderKey .. "] has an invalid token.")
    if (self.conf.sends_unauthorized == true) then
      local invalidTokenString = "Invalid token for request header: " .. tokenHeaderKey
      self:SendOperationOutcome(401, invalidTokenString)
    else
      kong.log.info("Falling through to default method.")
    end
  end

-- end of HealthApisTokenProtectedOperation:takeActionForInvalidToken()
end

--
-- Sends an operationOutcome to the user with a given status code and message value
--
function HealthApisTokenProtectedOperation:SendOperationOutcome(statusCode, message)
  local OPERATIONAL_OUTCOME_TEMPLATE =
    '{ "resourceType": "OperationOutcome",\n' ..
    '  "id": "exception",\n' ..
    '  "text": {\n' ..
    '      "status": "additional",\n' ..
    '      "div": "<div xmlns=\\"http://www.w3.org/1999/xhtml\\"><p>%s</p></div>"\n' ..
    '  },\n' ..
    '  "issue": [\n' ..
    '      {\n' ..
    '          "severity": "error",\n' ..
    '          "code": "exception",\n' ..
    '          "details": {\n' ..
    '              "text": "%s"\n' ..
    '          }\n' ..
    '      }\n' ..
    '  ]\n' ..
    '}'

    kong.log.info("Responding with " .. statusCode .. ":" .. message)
    ngx.status = statusCode
    ngx.header["Content-Type"] = "application/json"

    ngx.say(string.format(OPERATIONAL_OUTCOME_TEMPLATE, message, message))

    ngx.exit(statusCode)

-- end of HealthApisTokenProtectedOperation:SendOperationOutcome()
end

-- end of HealthApisTokenProtectedOperation plugin
return HealthApisTokenProtectedOperation;
