--
-- This plugin allows requests for one user be swapped with results from a test user.
-- It is used to allow developers with ID.me accounts but no VA records be swapped to
-- allow access to test data.
-- This plugin will replace known 'doppelganger' ICNs (typically ICNs of developers or
-- support staff) in incomming HTTP requests with a known test patient user
-- Responses will reverse the translation so that links or ICNs in the response
-- can be presented in terms of the original request.
--
-- An example:
-- I am a developer with an ID.me account but no records at the VA. My ICN is 999.
-- This plugin is configured such that 999 is a registered doppelganger for test
-- patient 123. Using the Apple Health app, I make a request for /Condition?patient=999
-- This plugin will request Condition?patient=123 instead. Just prior to returning the
-- response,  all occurrences of patient 123 are replaced with 999 to allow links
-- to continue to work.
--
--
-- WARNING
-- This plugin assumes that ICNs are unique enough to not naturally occur in text.
-- For example, the ICN 1017283132V631076 is easily recogized and replaced with
-- 1011537977V693883 using simple string replacement techniques.
--
local Doppelganger = require("kong.plugins.base_plugin"):extend()

Doppelganger.PRIORITY = 810 -- Just higher than request-transformer

function Doppelganger:new()
   Doppelganger.super.new(self,"health-apis-doppelganger")
end

--
-- The X-VA-ICN header must be present and is created by the health-apis-token-validator.
-- health-apis-token-validator must fire before Doppelganger.
--
function Doppelganger:access(conf)
   Doppelganger.super.access(self)
   local requestPath = ngx.var.upstream_uri
   local me = kong.request.get_header("X-VA-ICN")
   if (me == nil) then return end
   local mapping = self:findMappingForPath(conf, requestPath)
   if (mapping == nil) then return end
   local targetIcn = self:findTargetIcnForDoppelganger(mapping,me)
   if (targetIcn == nil) then return end
   -- The doppelganger ID will be stored in the context to be used later.
   -- The absence of this information indicates that no additional processing is required
   ngx.ctx.doppelganger = me
   ngx.ctx.targetIcn = targetIcn
   -- We need to override the client ICN with the doppelganger so that
   -- the new payload can pass verification in health-apis-patient-matching.
   kong.service.request.set_header("X-VA-ICN", targetIcn)
   kong.log.info("Doppelganger " .. ngx.ctx.doppelganger .. " for " .. targetIcn .. " on path " .. mapping.path)
   local newPath = string.gsub(requestPath, ngx.ctx.doppelganger, targetIcn)
   local newQuery = string.gsub(kong.request.get_raw_query(), ngx.ctx.doppelganger, targetIcn)
   kong.log.info("Changing " .. requestPath .. "?" .. kong.request.get_raw_query()
                    .. " to " .. newPath .. "?" .. newQuery)
   kong.service.request.set_path(newPath)
   kong.service.request.set_raw_query(newQuery)
end

function Doppelganger:findTargetIcnForDoppelganger(mapping,me)
   for i,entry in ipairs(mapping.doppelgangers) do
      if (entry.doppelganger == me) then return entry.target_icn end
   end
   return nil
end

function Doppelganger:findMappingForPath(conf,path)
   for i,mapping in ipairs(conf.mappings) do
      kong.log.info("checking path " .. mapping.path .. " against " .. path)
      if (string.match(path,mapping.path) ~= nil) then return mapping end
   end
   return nil
end

---
--- If the target ICN and the Doppelganger ICN are not the same length, the Content-Length
--- will be wrong. We don't actually know how long the response will be and can't tell
--- until we finish the body... at which point we don't have access to the headers.
---
function Doppelganger:header_filter()
   if (ngx.ctx.doppelganger == nil) then return end
   kong.response.clear_header('Content-Length')
end


--
-- The response is processed if the `doppelganger` attribute is set on the context.
-- Response body chunks are accumulated, then occurrences to the target test patient
-- are replaced by the doppelganger.
--
function Doppelganger:body_filter(conf)
   Doppelganger.super.body_filter(self)
   local ctx = ngx.ctx

   local doppelganger = ctx.doppelganger
   local targetIcn = ctx.targetIcn
   if (doppelganger == nil) then return end
   if (targetIcn == nil) then return end
   local chunk, eof = ngx.arg[1], ngx.arg[2]

   ctx.rt_body_chunks = ctx.rt_body_chunks or {}
   ctx.rt_body_chunk_number = ctx.rt_body_chunk_number or 1

   if eof then
      local chunks = table.concat(ctx.rt_body_chunks)
      local body = string.gsub(chunks,targetIcn,doppelganger)
      ngx.arg[1] = body or chunks
   else
      ctx.rt_body_chunks[ctx.rt_body_chunk_number] = chunk
      ctx.rt_body_chunk_number = ctx.rt_body_chunk_number + 1
      ngx.arg[1] = nil
   end
end

return Doppelganger
