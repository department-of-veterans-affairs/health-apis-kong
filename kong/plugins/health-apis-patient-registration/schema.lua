return {
  no_consumer = true,
  fields = {
    ids_url = {type = "string"},
    token_url = {type = "string"},
    token_timeout = {type = "number", default = 10000},
    static_refresh_token = {type = "string", default = ""},
    static_icn = {type = "string", default = ""},
  }
}
