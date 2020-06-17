return {
  no_consumer = true,
  --
  -- THIS IS A SAD HACK!
  -- The plugin will not compile if the configuration is left null. BOOOOOOO!
  -- We don't actually need this, but lets initialize a dummy value that we never use.
  --
  fields = {
    UNUSED = {type = "boolean", default = true}
  }
}
