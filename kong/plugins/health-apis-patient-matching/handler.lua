local HealthApisPatientMatching = require("kong.plugins.base_plugin"):extend()

function HealthApisPatientMatching:new()
   HealthApisPatientMatching.super.new(self,"health-apis-patient-matching")
end

--
-- Remember our internal X-VA-ICN header values for later use
--
function HealthApisPatientMatching:access(conf)
  HealthApisPatientMatching.super.access(self)
  local me = kong.request.get_header("X-VA-ICN")
  if (me == nil) then return end
  kong.log.info("Receiving X-VA-ICN Header as: " .. me)
  ngx.ctx.icnHeader = me
end

--
-- Compare the values of the X-VA-ICN header to that of the X-VA-INCLUDES-ICNS headers
-- If they match, allow the response through.
-- If there is a mismatch, response with error code 403 Forbidden.
--
function HealthApisPatientMatching:header_filter(conf)
  local me = ngx.ctx.icnHeader
  local included = kong.response.get_header("X-VA-INCLUDES-ICN")
  if (included == nil) then
    kong.log.info("No X-VA-INCLUDES-ICN header was provided.")
    ngx.ctx.matching = "MISSING"
  end
  for word in string.gmatch(included, '([^,]+)') do
    if (word ~= me) then
      kong.log.info("Mismatched ICNs. Client ICN " .. me .. " does not equal an included ICN of " .. word)
      ngx.ctx.matching = "MISMATCHED"
    end
  kong.log.info("Matching ICNs. Client ICN " .. me .. " does equals the included ICN of " .. word)
  end
end

function HealthApisPatientMatching:body_filter(conf)
  HealthApisPatientMatching.super.body_filter(self)
  self.conf = conf

  local result = ngx.ctx.matching
  kong.log.info("MATCHING STATE: " .. result)
  if (result == nil) then return end
  if (result == "MISSING") then
    self.sendOperationOutcome(400, "Missing ICN.")
  end
  if (result == "MISMATCH") then
    self.sendOperationOutcome(403, "Token not allowed access to this patient.")
  end
end

--
-- Sends an operationOutcome to the user with a given status code and message value
--
function HealthApisPatientMatching:sendOperationOutcome(statusCode, message)
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

-- end of HealthApisPatientMatching:SendOperationOutcome()
end

return HealthApisPatientMatching;
