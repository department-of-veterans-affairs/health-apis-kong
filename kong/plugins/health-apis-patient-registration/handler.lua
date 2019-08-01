local HealthApisPatientRegistration = require("kong.plugins.base_plugin"):extend()

local http = require "resty.http"
local cjson = require "cjson.safe"

local find = string.find
local format = string.format

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

local BAD_AUTHORIZE_RESPONSE = "Authorization failed."
local BAD_IDS_RESPONSE = "IDS failed."
local MISSING_ICN = "Token response missing ICN."

function HealthApisPatientRegistration:new()
  HealthApisPatientRegistration.super.new(self, "health-apis-patient-registration")
end

function HealthApisPatientRegistration.split(str, delimiter)
  local result = { }
  local from  = 1
  local delim_from, delim_to = string.find( str, delimiter, from  )
  while delim_from do
    table.insert( result, string.sub( str, from , delim_from-1 ) )
    from  = delim_to + 1
    delim_from, delim_to = string.find( str, delimiter, from  )
  end
  table.insert( result, string.sub( str, from  ) )
  return result
end

function HealthApisPatientRegistration:access(conf)
  HealthApisPatientRegistration.super.access(self)
  kong.log.info("Patient registration")
  self.conf = conf

  if (self.conf.ids_url == nil) then
    ngx.log(ngx.ERR, "IDS URL not set.")
    return
  end

  -- Required by lua (request body data not loaded by default)
  ngx.req.read_body()

  local body_data, errors = ngx.req.get_body_data()

  if not body_data then
    ngx.log(ngx.ERR, "failed to get post args: ", errors)
    return
  end

  local post_args, errors = ngx.req.get_post_args()
  local requestRefreshToken = post_args["refresh_token"]

  if (requestRefreshToken ~= nil and requestRefreshToken == self.conf.static_refresh_token) then
    ngx.log(ngx.INFO, "Static refresh token requested")
    self:register_patient(self.conf.static_icn)
    --only register the static patient, no token call required
    return
  end

  local client = http.new()
  client:set_timeout(self.conf.token_timeout)

  -- Do the hack that switches requests from using basic auth for client_id and client_secret to
  -- using a form encoded body
  local body_with_creds = self:switch_from_basic_auth_to_body_credentials(post_args)
  if (body_with_creds ~= nil) then body_data=body_with_creds end

  kong.log.info("Requesting token from " .. self.conf.token_url)
  local token_res, err = client:request_uri(self.conf.token_url, {
    method = "POST",
    ssl_verify = false,
    headers = {
      ["Content-Type"] = "application/x-www-form-urlencoded",
    },
    body = body_data,
  })

  if not token_res then
    -- Error making request to validate endpoint
    kong.log.err("Failed to get token from " .. self.conf.token_url .. " error " .. err)
    return self:send_fhir_response(404, BAD_AUTHORIZE_RESPONSE)
  end

  -- Get the status and body of the token request
  -- So we can be done with the connection
  local token_res_status = token_res.status
  local token_res_body = token_res.body

  kong.log.info("Authorization status " .. token_res_status)
  -- If unauthorized, we block the user
  if (token_res_status == 401) then
    return self:send_fhir_response(401, BAD_AUTHORIZE_RESPONSE)
  end

  -- An unexpected condition
  if (token_res_status < 200 or token_res_status > 299) then
    return self:send_fhir_response(500, BAD_AUTHORIZE_RESPONSE)
  end

  local token_res_json = cjson.decode(token_res_body)
  self:register_patient(token_res_json.patient)

  return self:send_response(token_res_status, token_res_body)
end

-- HACK: The Okta /token endpoint doesn't do well with client credentials specified as a
-- basic Authorization header. This method will re-write the body to include credentials
-- using the header information.
-- Returns: nil if the body cannot be constructed.
function HealthApisPatientRegistration:switch_from_basic_auth_to_body_credentials(post_args)
  local authorization=ngx.req.get_headers()["Authorization"]
  if (authorization == nil) then return nil end
  kong.log.info("Switching request from basic authentication to client credentials in body")
  local base64_auth = string.gsub(authorization, "^Basic ","")
  if (base64_auth == nil) then
    kong.log.info("Authorization is not Basic type")
    return nil
  end
  local decoded_auth = ngx.decode_base64(base64_auth)
  if (decoded_auth == nil) then
    kong.log.warn("Failed to decode Authorization header")
    return nil
  end

  local client_id_and_secret = HealthApisPatientRegistration.split(decoded_auth,":")
  local client_id=client_id_and_secret[1]
  if (client_id == nil) then
    kong.log.warn("Missing client_id in Authorization header")
    return nil
  end

  local client_secret=client_id_and_secret[2]
  if (client_secret == nil) then
    kong.log.warn("Missing client_secret in Authorization header")
    return nil
  end

  local grant_type=post_args["grant_type"]
  if (grant_type == nil) then
    kong.log.warn("Missing grant_type in body")
    return nil
  end

  local code=post_args["code"]
  if (code == nil) then
    kong.log.warn("Missing code in body")
    return nil
  end

  local redirect_uri=post_args["redirect_uri"]
  if (redirect_uri == nil) then
    kong.log.warn("Missing redirect_uri in body")
    return nil
  end

  return ngx.encode_args({
    grant_type = grant_type,
    code = code,
    redirect_uri = redirect_uri,
    client_id = client_id,
    client_secret = client_secret
  })

end

function HealthApisPatientRegistration:register_patient(patient_icn)
  if (self.conf.register_patient == false) then return end

  if (patient_icn == nil) then
    return self:send_fhir_response(500, MISSING_ICN)
  end

  local ids_client = http.new()
  ids_client:set_timeout(self.conf.token_timeout)

  local ids_body_data = '[\n' ..
    '{\n' ..
    '    "system": "CDW",\n' ..
    '    "resource": "PATIENT",\n' ..
    '    "identifier": "' .. patient_icn .. '"\n' ..
    '}\n' ..
    ']'

  local ids_res, err = ids_client:request_uri(self.conf.ids_url, {
    method = "POST",
    ssl_verify = false,
    headers = {
      ["Content-Type"] = "application/json",
    },
    body = ids_body_data,
  })

  if not ids_res then
    -- Error making request to validate endpoint
    return self:send_fhir_response(404, BAD_IDS_RESPONSE)
  end

  -- Get the status and body of the verification request
  -- So we can be done with the connection
  local ids_res_status = ids_res.status
  local ids_res_body = ids_res.body

  -- If unauthorized, we block the user
  if (ids_res_status == 401) then
    return self:send_fhir_response(401, BAD_IDS_RESPONSE)
  end

  -- An unexpected condition
  if (ids_res_status < 200 or ids_res_status > 299) then
    return self:send_fhir_response(500, BAD_IDS_RESPONSE)
  end

end


-- Format and send the response to the client
function HealthApisPatientRegistration:send_fhir_response(status_code, message)

  ngx.status = status_code
  ngx.header["Content-Type"] = "application/json"

  ngx.say(format(OPERATIONAL_OUTCOME_TEMPLATE, message, message))

  ngx.exit(status_code)
end

function HealthApisPatientRegistration:send_response(status_code, message)

  ngx.status = status_code
  ngx.header["Content-Type"] = "application/json"
  ngx.say(message)
  ngx.exit(status_code)

end


HealthApisPatientRegistration.PRIORITY = 1011

return HealthApisPatientRegistration
