return {
  no_consumer = true,
  fields = {
    static_refresh_token = {type = "string", default = ""},
    static_access_token = {type = "string", default = ""},
    static_icn = {type = "string", default = ""},
    static_scopes = {type = "string", default = ""},
    static_expiration = {type = "number", default = 3599}
  }
}
