# health-apis-kong

## health-apis Kong image

A custom Dockerfile builds on the base Kong image.  It adds the custom plugins as well as an `on-start.sh` script from AWS S3.

## health-apis-token-validator Kong Plugin

A Kong plugin to validate a supplied OAuth token.  It can be installed on a Kong instance and configured to run against the entire instance, specific API's, or specific routes.

### Building

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

## health-apis-patient-registration Kong Plugin

A Kong plugin to handle patient registration with the Identity Service as part of the access token retrieval.


### Configuration

Once the plugin is installed on the Kong instance, it can be configured via the Admin port.  Replace config entries with the correct values for your environment.

```
{
    "name": "health-apis-patient-registration",
    "config": {
        "ids_url": "{{ids-endpoint}}/api/v1/ids"
        "token_url": "{{token-endpoint}}'"
        "token_timeout": "10000"
        "static_refresh_token": "{static-refresh-token}",
        "static_icn": "{static-icn}"
    },
    "enabled": true
}
```

> Note:  The static patient still needs to register with the Identity Service, so that use case requires the additional config values.

## Local development

A docker-compose script exists for local development of plugins.  Ensure you first build `docker build -t health-apis-kong:latest .` to test your changes.

`COPY kong/plugins/ /usr/local/share/lua/5.1/kong/plugins/` in the Dockerfile copies the custom plugins into the image.

> Note:  Uncomment `COPY kong.yml /etc/kong/kong.yml` in the Dockerfile to utilize the local kong.yml, otherwise it will pull from S3 and not include your configurations.

`docker-compose up`

