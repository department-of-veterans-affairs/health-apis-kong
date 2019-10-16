return {
  no_consumer = true,
  --
  -- THIS IS A SAD HACK!
  -- The plug-in will not compile if the fields object is left null. BOOOOOOO!
  -- We don't actually need this, but lets initialize a dummy value that we never use.
  --
  fields = {
    UNUSED = {type = "boolean", default = true}
  }
}
