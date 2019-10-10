return {
  no_consumer = true,
  fields = {
    request_header_key = {type = "string", required = true},
    allowed_tokens = {type = "array", required = true},
    send_boolean_header = {type = "string"},
    sends_unauthorized = {type = "boolean", default = true}
  }
}
