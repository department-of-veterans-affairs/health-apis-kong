local HealthApisTokenValidator = require("kong.plugins.base_plugin"):extend()

local http = require "resty.http"
local cjson = require "cjson.safe"

local find = string.find
local format = string.format

local TYPE_JSON = "application/json"

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

local INVALID_TOKEN = "invalid token."
local TOO_MANY_REQUESTS = "Too many requests."
local BAD_VALIDATE_ENDPOINT = "Validate endpoint not found."
local VALIDATE_ERROR = "Error validating token."
local ICN_MISSING = "Patient identifier not supplied."
local TOKEN_MISMATCH = "Token not allowed access to this patient."
local SCOPE_MISMATCH = "Token not granted requested scope."
local PATIENT_SEARCH_NOT_ALLOWED = "Patient searching disabled."

function HealthApisTokenValidator:new()
  HealthApisTokenValidator.super.new(self, "health-apis-token-validator")
end

function HealthApisTokenValidator:access(conf)
  HealthApisTokenValidator.super.access(self)
  kong.log.info("Validating token")

  self.conf = conf

  if (ngx.req.get_headers()["Authorization"] == nil) then
    kong.log.info("Missing header: Authorization")
    return self:send_response(401, INVALID_TOKEN)
  end

  local token = self:get_token_from_auth_string(ngx.req.get_headers()["Authorization"])
  local tokenIcn = nil

  if (token == self.conf.static_token) then
    kong.log.info("Static token")
    tokenIcn = self.conf.static_icn
  else
    local responseJson = self:check_token()

    tokenIcn = responseJson.data.attributes["va_identifiers"].icn
    responseScopes = responseJson.data.attributes.scp
    self:check_scope(responseScopes)

  end

  self:check_icn(tokenIcn)

  kong.service.request.set_header("X-VA-ICN", tokenIcn)
  kong.log.info("Token validated and ICN header added to request")
end

function HealthApisTokenValidator:check_token()

  local client = http.new()
  client:set_timeout(self.conf.verification_timeout)

  kong.log.info("Checking token with " .. self.conf.verification_url);

  local verification_res, err = client:request_uri(self.conf.verification_url, {
    method = "GET",
    ssl_verify = false,
    headers = {
      Authorization = ngx.req.get_headers()["Authorization"],
      Host = self.conf.verification_host,
      apiKey = self.conf.api_key,
    },
  })

  if not verification_res then
    kong.log.err("Missing verification response" .. err)
    ngx.say("failed to request: ", err)
    -- Error making request to validate endpoint
    return self:send_response(404, BAD_VALIDATE_ENDPOINT)
  end

  -- Get the status and body of the verification request
  -- So we can be done with the connection
  local verification_res_status = verification_res.status
  local verification_res_body = verification_res.body

  kong.log.info("Verification response is " .. verification_res.status)
  kong.log.info(verification_res_body)

  -- If unauthorized, we block the user
  if (verification_res_status == 401) then
    return self:send_response(401, INVALID_TOKEN)
  end

  -- If authorization service is too busy, we need to tell the user to slow down
  if (verification_res_status == 429) then
    kong.log.err("Authorization request has been throttled")
    return self:send_response(429, TOO_MANY_REQUESTS)
  end

  -- An unexpected condition
  if (verification_res_status < 200 or verification_res_status > 299) then
    return self:send_response(500, VALIDATE_ERROR)
  end

  return cjson.decode(verification_res_body)

end

function HealthApisTokenValidator:check_icn(tokenIcn)

  local requestIcn = self:get_request_icn()

  -- For DQ we need to disallow complex patient searches, e.g. /Patient?name=xxx&gender=female
  -- So for Patient resources, we will require that an ICN be supplied in the request
  if (requestIcn == nil and self:get_requested_resource_type() == "Patient") then
    ngx.log(ngx.INFO, "Requested ICN does not match token")
    return self:send_response(403, PATIENT_SEARCH_NOT_ALLOWED)
  end

  if (requestIcn == nil) then
    if (self:is_request_search()) then
      return self:send_response(403, ICN_MISSING)
    end
  elseif (requestIcn ~= tokenIcn) then
    ngx.log(ngx.INFO, "Requested ICN does not match token")
    return self:send_response(403, TOKEN_MISMATCH)
  end

end

function HealthApisTokenValidator:check_scope(tokenScope)

  local requestedResource = nil

  if (self.conf.custom_scope_validation_enabled) then
    requestedResource = self.conf.custom_scope
  else
    requestedResource = self:get_requested_resource_type()
  end

  local requestScope = "patient/" .. requestedResource .. ".read"

  if (self:check_for_array_entry(tokenScope, requestScope) ~= true) then
    ngx.log(ngx.INFO, "Requested resource scope not granted to token")
    return self:send_response(403, SCOPE_MISMATCH)
  end

end

function HealthApisTokenValidator:check_for_array_entry(array, entry)

  local scopes = "";
  for k, v in pairs(array) do
    scopes=scopes .. " " .. v
    if (v == entry) then
      kong.log.info("Found scope " .. v)
      return true
    end
  end
  kong.log.info("Did not find scope '" .. entry .. "' in " .. scopes);
  return false
end

function HealthApisTokenValidator:get_token_from_auth_string(authString)

  i, j = find(authString, "Bearer ")
  if (i ~= nil) then
    return string.sub(authString, j+1)
  else
    return "Bad Token"
  end

end

function HealthApisTokenValidator:is_request_read()
  if (string.match(ngx.var.uri, "/[%w]+$") == "/search") then
    return false
  end

  -- Note: This works for the Urgent Care resource as a side effect of
  -- the "%a*" (any *letter* repeating) rejects /r4/{resource} as a read
  local requestedResourceRead = string.match(ngx.var.uri, "/%a*/[%w%-]+$")
  return (requestedResourceRead ~= nil)
end

function HealthApisTokenValidator:is_request_search()
  return (self:get_search_icn() ~= nil)
end

function HealthApisTokenValidator:get_request_icn()
  if (self:is_request_read()) then
    return self:get_read_icn()
  else
    return self:get_search_icn()
  end

end

function HealthApisTokenValidator:get_read_icn()

  i, j = find(ngx.var.uri, "/Patient/")
  if (i ~= nil) then
    local pathIcn = string.sub(ngx.var.uri, j+1)
    return pathIcn
  end

end

function HealthApisTokenValidator:get_search_icn()

  local patientIcn = ngx.req.get_uri_args()["patient"];
  local _idIcn = ngx.req.get_uri_args()["_id"]

  if (patientIcn ~= nil) then
    return patientIcn
  elseif (_idIcn ~= nil) then
    --_id is only a valid search for Patient
    if (self:get_requested_resource_type() == "Patient") then
      return _idIcn
    end
  else
  end

end

function HealthApisTokenValidator:get_requested_resource_type()

  local requestedResource = nil

  if (self:is_request_read()) then
    local requestedResourceRead = string.match(ngx.var.uri, "/%a*/[%w%-]+$")
    i, j = find(requestedResourceRead, "/%a*/")
    if (i ~= nil) then
      requestedResource = string.sub(requestedResourceRead, i+1, j-1)
    end
  else
    requestedResource = string.match(ngx.var.uri, "%a*$")
  end

  return requestedResource

end

-- Format and send the response to the client
function HealthApisTokenValidator:send_response(status_code, message)

  kong.log.info("Responding with " .. status_code .. ":" .. message)
  ngx.status = status_code
  ngx.header["Content-Type"] = TYPE_JSON

  ngx.say(format(OPERATIONAL_OUTCOME_TEMPLATE, message, message))

  ngx.exit(status_code)
end


HealthApisTokenValidator.PRIORITY = 1010

return HealthApisTokenValidator
