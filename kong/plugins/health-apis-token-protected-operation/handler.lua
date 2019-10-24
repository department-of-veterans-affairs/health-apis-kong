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

  local tokenHeaderKey = self.conf.request_header_key
  local tokenHeaderValue = ngx.req.get_headers()[tokenHeaderKey]


  -- If request doesnt contain header, skip
  if (tokenHeaderValue == nil) then
    if (self.conf.allow_empty_header == true) then
      -- Make sure nobodys getting around validation by setting the application
      -- header without the request header
      self:setApplicationHeader(false)
      return
    else
       tokenHeaderValue = ''
    end
  end

--
-- The good stuff:
-- Determine if the value of the header is in the allowed token values
--

  kong.log.info("Validating Token Received Under Header: " .. tokenHeaderKey)

  local tokenValid = self:validateToken(tokenHeaderKey, tokenHeaderValue)

  self:setApplicationHeader(tokenValid)

  -- If we get here, we checked a token. Let's make sure we perform necessary
  -- actions if its invalid.
  if (tokenValid == false) then
    self:takeActionForInvalidToken(tokenHeaderKey)
  end

-- end of HealthApisTokenProtectedOperation:access()
end

--
-- Validates the token against a list of allowed_tokens provided in the
-- plugins configration
--
function HealthApisTokenProtectedOperation:validateToken(tokenHeaderKey, tokenHeaderValue)
  -- Invalid Until Proven Valid
  local isValidToken = false
  for i,token in ipairs(self.conf.allowed_tokens) do
    if (token == tokenHeaderValue) then
      kong.log.info("Header:[" .. tokenHeaderKey .. "] has valid token.")
      isValidToken = true
      break
    end
  end

  return isValidToken

-- end of HealthApisTokenProtectedOperation:validateToken()
end

--
-- send a 401
--
function HealthApisTokenProtectedOperation:takeActionForInvalidToken(tokenHeaderKey)
  kong.log.info("Header:[" .. tokenHeaderKey .. "] has an invalid token.")
  local invalidTokenString = "Invalid token for request header: " .. tokenHeaderKey
  self:sendOperationOutcome(401, invalidTokenString)
-- end of HealthApisTokenProtectedOperation:takeActionForInvalidToken()
end

--
-- Set the boolean application header if one was given in the configuration
--
function HealthApisTokenProtectedOperation:setApplicationHeader(value)
  if (self.conf.send_boolean_header ~= nil) then
    kong.service.request.set_header(self.conf.send_boolean_header, value)
  end
-- end of HealthApisTokenProtectedOperation:setApplicationHeader()
end

--
-- Sends an operationOutcome to the user with a given status code and message value
--
function HealthApisTokenProtectedOperation:sendOperationOutcome(statusCode, message)
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
