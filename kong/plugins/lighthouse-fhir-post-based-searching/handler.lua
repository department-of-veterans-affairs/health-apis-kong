-- Based on the implementation outlined in the link below
-- http://hl7.org/fhir/R4/http.html#search

local PostBasedSearching = require("kong.plugins.base_plugin"):extend()

-- Reform before other plugins.
-- If the patient parameter is in the body of the request, other plugins won't be
-- able to find it
PostBasedSearching.PRIORITY = 1020

function PostBasedSearching:new()
  PostBasedSearching.super.new(self, "lighthouse-fhir-post-based-searching")
end

--
-- Entrypoint of plugin
--
function PostBasedSearching:access(conf)
  PostBasedSearching.super.access(self)

  -- Validate the request before continuing
  local requestPath = ngx.var.upstream_uri
  if (not self:isFhirPostSearch(requestPath, kong.request.get_method(), kong.request.get_header("Content-Type"))) then
    return
  end

  -- Transform different parts of the query
  local queryParamString = kong.request.get_raw_query()
  local postRequestBody = kong.request.get_raw_body()
  local fhirPath = string.gsub(requestPath, "/_search", "")
  local getRequestQueryString = self:combineParameters(queryParamString, postRequestBody)

  -- Rebuild Query
  kong.service.request.set_raw_body("")
  kong.service.request.set_method("GET")
  kong.service.request.set_header("Content-Type", "application/fhir+json")
  kong.service.request.set_path(fhirPath)
  kong.service.request.set_raw_query(getRequestQueryString)

  kong.log.info("POST " .. requestPath .. "?" .. queryParamString .. " with body " .. postRequestBody ..
    " -> GET " .. fhirPath .. "?" .. getRequestQueryString)

end -- PostBasedSearching:access

--
-- Note that in the POST variant, parameters may appear in both the URL and the body.
-- Parameters have the same meaning in either place. Since parameters can repeat,
-- putting them in both places is the same as repeating them.
--
function PostBasedSearching:combineParameters(queryParams, requestBody)
  if (queryParams ~= "" and requestBody ~= "") then
    return queryParams .. "&" .. requestBody
  end
  return queryParams .. requestBody
end -- PostBasedSearching:combineQueryParameters

--
-- Checks that the request path matches [base]/[type]/_search{?[parameters]{&_format=[mime-type]}}
-- AND the method is POST
-- AND the Content-Type is application/x-www-form-urlencoded
--
function PostBasedSearching:isFhirPostSearch(requestPath, requestMethod, contentType)
  -- method is POST
  return requestMethod == "POST"
    -- content-type is application/x-www-form-urlencoded
    and contentType == "application/x-www-form-urlencoded"
    -- Path is correct for fhir POST searching
    and string.find(requestPath, "[A-Za-z]+/_search") ~= nil
end -- PostBasedSearching:isFhirPostSearch

-- THE END
return PostBasedSearching
