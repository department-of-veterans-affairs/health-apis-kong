return {
  no_consumer = true,
  --
  -- THIS IS A SAD HACK!
  -- The plug-in will not compile if the fields object is left null. BOOOOOOO!
  -- We initialize a dummy value that we never use.
  --
  fields = {
    UNUSED = {type = "boolean", default = false}
  }
}
