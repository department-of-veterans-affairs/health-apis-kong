local HealthApisPatientMatching = require("kong.plugins.base_plugin"):extend()

HealthApisPatientMatching.PRIORITY = 805 -- After the Doppelganger but before Response Transformer


function HealthApisPatientMatching:new()
   HealthApisPatientMatching.super.new(self,"health-apis-patient-matching")
end

--
-- Remember our internal X-VA-ICN header values for later use during
-- patient matching validation.
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
function HealthApisPatientMatching:header_filter()

  --
  -- Pass through any downstream service failures. Proceed to patient matching
  -- only on the 200 series status codes.
  --
  local status = kong.response.get_status()
  if (status < 200 and status > 299) then
    return
  end

  --
  -- If we are missing the INCLUDES-ICN header, fail with 403 Forbidden.
  --
  local included = kong.response.get_header("X-VA-INCLUDES-ICN")
  if (included == nil) then
    kong.log.info("MISSING X-VA-INCLUDES-ICN HEADER. CANNOT PROCEED WITH PATIENT MATCHING")
    ngx.ctx.matching_failure = true
    kong.response.set_status(403)
    return
  end

  --
  -- If INCLUDES-ICN header is "NONE" then
  -- patient data is NOT included in the payload.
  -- Resources like Medication which are 'patient agnostic' will provide this.
  -- Responses like empty bundles are also 'patient agnostic'.
  -- In these cases, we are done here.
  --
  if (included == "NONE") then
    kong.log.info("The response payload is patient agnostic.")
    return
  end

  --
  -- We did not receive the private X-VA-ICN HEADER
  -- Unable to verify patient-matching, we must 403 forbidden the payload.
  --
  local me = ngx.ctx.icnHeader
  if (me == nil) then
    kong.log.info("MISSING X-VA-ICN HEADER. CANNOT PROCEED WITH PATIENT MATCHING.")
    ngx.ctx.matching_failure = true
    kong.response.set_status(403)
    return
  end

  --
  -- The header X-VA-ICN is not matching X-VA-INCLUDES-ICN.
  -- Do not allow the client to have access to ICN's other than his own.
  -- Fail with 403 Forbidden and an Operation Outcome.
  --
  for word in string.gmatch(included, '([^,]+)') do
    if (word ~= me) then
      kong.log.info("MISMATCHING ICNs. CLIENT ICN " .. me .. " DOES NOT EQUAL INCLUDED ICN OF " .. word)
      ngx.ctx.matching_failure = true
      kong.response.set_status(403)
      return
    end

  kong.log.info("Matching ICNs. Client's provided ICN " .. me .. " equals response ICN of " .. word)
  end
end

--
-- After the header_filter, the body_filter processes the response.
-- Analyzing the context object ngx.ctx for matching failures, we
-- now must prepare the payload if patient matching failed.
-- We generate an Operational Outcome for 403 Forbidden,
-- and remove the payload for any forbidden requests.
-- Others pass through normally.
--
function HealthApisPatientMatching:body_filter(conf)
  HealthApisPatientMatching.super.body_filter(self)

  local ctx = ngx.ctx
  local failure = ctx.matching_failure

  --
  -- If Patient Matching detected no problems, then we allow the response through.
  -- Else, we replace the response chunks with an Operational Outcome
  -- wiping out the payload. Status code is set during the header_filter.
  -- We cannot write to status_code in the body_filter.
  --
  if (not failure) then return end

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
  local message = "Token not allowed access to this patient."

  local chunk, eof = ngx.arg[1], ngx.arg[2]
  ctx.rt_body_chunks = ctx.rt_body_chunks or {}
  ctx.rt_body_chunk_number = ctx.rt_body_chunk_number or 1

  if eof then
     local body = nil
       body = string.format(OPERATIONAL_OUTCOME_TEMPLATE, message, message)
       kong.log.info("Setting OO: " .. body)
     ngx.arg[1] = body
  else
     ctx.rt_body_chunks[ctx.rt_body_chunk_number] = chunk
     ctx.rt_body_chunk_number = ctx.rt_body_chunk_number + 1
     ngx.arg[1] = nil
  end

end

return HealthApisPatientMatching;
