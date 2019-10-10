return {
  no_consumer = true,
  fields = {
    request_header_key = {type = "string", required = true},
    allowed_tokens = {type = "array", required = true},
    application_header_key = {type = "string"},
    sends_unauthorized = {type = "boolean", default = true}
  }
}
