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
  kong.log.info("Patient registration")
  HealthApisPatientRegistration.super.access(self)

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


  if (body_data ~= nill) then
    kong.log.info("BODY " .. body_data)
  end

  local authorization=ngx.req.get_headers()["Authorization"]
  if (authorization ~= nil) then
    kong.log.err("AUTH " .. authorization)
    local base64_auth = string.gsub(authorization, "^Basic ","")
    local decoded_auth = ngx.decode_base64(base64_auth)
    kong.log.err("DECODED " .. decoded_auth)
    local client_id_and_secret = HealthApisPatientRegistration.split(decoded_auth,":")
    -- TODO check array size
    local client_id=client_id_and_secret[1]
    local client_secret=client_id_and_secret[2]
    kong.log.err("WOW " .. client_id .. " / " .. client_secret)
    -- WE WANT:
    -- grant_type=authorization_code&code=3IWCfkyg7smhg_3PsUdr&redirect_uri=https%3A%2F%2Fapp%2Fafter-auth&client_id=0oa2dmpuz9fMYIujw2p7&client_secret=XTDgBe7S3iXOCDL7Wc8H49H43NJnX5FT6RoTcjwR
    -- WE HAVE:
    -- grant_type=authorization_code&code=Rn5saoHhFAIY-c1x7oD5&redirect_uri=https%3A%2F%2Fapp%2Fafter-auth&client_id=0oa2dmpuz9fMYIujw2p7
    local grant_type=post_args["grant_type"]
    local code=post_args["code"]
    local redirect_uri="https%3A%2F%2Fapp%2Fafter-auth"
    -- post_args["redirect_uri"]
    body_data="grant_type=" .. grant_type
      .. "&code=" .. code
      .. "&redirect_uri=" .. redirect_uri
      .. "&client_id=" .. client_id
      .. "&client_secret=" .. client_secret
    kong.log.info("BODY " .. body_data)
  end
  kong.log.info("BODY " .. body_data)

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
  -- self:register_patient(token_res_json.patient)

  return self:send_response(token_res_status, token_res_body)

end

function HealthApisPatientRegistration:register_patient(patient_icn)

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
