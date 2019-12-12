local typedefs = require "kong.db.schema.typedefs"
return {
   name = "health-apis-doppelganger",
   fields = {
      {
         consumer = typedefs.no_consumer
      },
      {
         config = {
            type = "record",
            fields = {
               {
                  mappings = {
                     type = "array",
                     elements = {
                        type = "record",
                        fields = {
                           { path = { type = "string", required = true } },
                           {
                              doppelgangers = {
                                 type = "array",
                                 elements = {
                                    type = "record",
                                    fields = {
                                       { target_icn = { type = "string" } },
                                       { doppelganger = { type = "string" } }
                                    } -- ...doppelgangers.elements.fields
                                 } -- ...doppelgangers.elements
                              } -- ...doppelgangers
                           } -- config.fields.mappings.elements.fields[1] (doppelgangers)
                        } -- config.fields[0].mappings.elements.fields
                     } -- config.fields[0].mappings.elements
                  } -- config.fields[0].mappings.elements
               } -- config.fields[0] (mappings)
            } -- fields[1].config.fields
         } -- fields[1].config
      } -- fields[1] (config)
   } -- fields
} -- return
