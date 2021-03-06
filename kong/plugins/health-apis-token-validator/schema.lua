return {
  no_consumer = true,
  fields = {
    verification_url = {type = "string"},
    verification_timeout = {type = "number", default = 10000},
    verification_host = {type = "string"},
    static_token = {type = "string", default = ""},
    static_icn = {type = "string", default = ""},
    custom_scope_validation_enabled = {type = "boolean", default = false},
    custom_scope = {type = "string", default = ""},
    api_key = {type = "string"},
    audience = { type = "string", default = ""}
  }
}
