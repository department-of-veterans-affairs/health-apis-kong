# health-apis-kong

## health-apis Kong image

A custom Dockerfile builds on the base Kong image.  It adds the custom plugins as well as an `on-start.sh` script from AWS S3.

## health-apis-token-validator Kong Plugin

A Kong plugin to validate a supplied OAuth token.  It can be installed on a Kong instance and configured to run against the entire instance, specific API's, or specific routes.

### Building

> Luarocks must be installed to build.

Run `luarocks pack health-apis-token-validator-0.1-2.rockspec` to package the plugin into a Lua "rock" which can then be copied and installed on a Kong instance.

### Configuration

Once the plugin is installed on the Kong instance, it can be configured via the Admin port.  Replace config entries with the correct values for your environment.

```
{
    "name": "health-apis-token-validator",
    "config": {
        "verification_url": "{verification-url}",
        "verification_timeout": {verification-timeout},
        "api_key": "{api-key}",
        "static_token": "{static-token}",
        "static_icn": "{static-icn}"
    },
    "enabled": true
}
```



## health-apis-static-token-handler Kong Plugin

A Kong plugin to return a static access token used for customer testing

> Luarocks must be installed to build.

Run `luarocks pack health-apis-static-token-handler-0.1-1.rockspec` to package the plugin into a Lua "rock" which can then be copied and installed on a Kong instance.


### Configuration

Once the plugin is installed on the Kong instance, it can be configured via the Admin port.  Replace config entries with the correct values for your environment.

```
{
    "name": "health-apis-static-token-handler",
    "config": {
        "static_refresh_token": "{static-refresh-token}",
        "static_scopes": "{static-scopes}",
        "static_access_token": "{static-access-token}",
        "static_expiration": 3599,
        "static_icn": "{static-icn}"
    },
    "enabled": true
}
```


## Local development

The base Kong docker-compose file has been updated to mount the two plugins as volumes within the Kong docker container.  Along with the `KONG_PLUGINS` config defining the additional plugins as enabled.

`docker-compose up`

Docker must be allowed share access to the location of your local repo.

> Note:   There have been issues observed mounting volumes when logged in to your machine with an Active Directory account

With volume mounting, you can use your local machine's text editor of choice for testing changes of the Lua files.  A simple `kong reload` will update your changes within the kong instance.