return {
  no_consumer = true,
  fields = {
    request_header_key = { type = "string", required = true },
    allowed_tokens = { type = "array", required = true },
    send_boolean_header = { type = "string" },
    allow_empty_header = { type = "boolean", default = false }
  }
}
