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
        "static_icn": "{static-icn}",
        "custom_scope_validation_enabled": "{custom-scope-validation-enabled}"
        "custom_scope": "{custom-scope}"
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

This Kong plugin serves two purposes.
1. Handle patient registration with the Identity Service as part of the access token retrieval.
   This can be disabled in the plugin configuration, set `register_patient = false`.
2. Implement a work around to limitations with the Okta OAuth server that is rejected Access token requests
   to `/token` where the `client_id` and `client_secret` are passed as a Basic Authentication header.
   This work around will convert the `Authorization` header in to a client credentials in the post body.

### Configuration

Once the plugin is installed on the Kong instance, it can be configured via the Admin port.  Replace config entries with the correct values for your environment.

```
{
    "name": "health-apis-patient-registration",
    "config": {
        "register_patient": true
        "ids_url": "{ids-endpoint}/api/v1/ids"
        "token_url": "{token-endpoint}'"
        "token_timeout": "10000"
        "static_refresh_token": "{static-refresh-token}",
        "static_icn": "{static-icn}"
    },
    "enabled": true
}
```

> Note:  The static patient still needs to register with the Identity Service, so that use case requires the additional config values.

## Local development

Local development can be done one of two ways:
1. The hard way
2. The magical way

#### The Hard Way
A docker-compose script exists for local development of plugins.  

`COPY kong/plugins/ /usr/local/share/lua/5.1/kong/plugins/` in the Dockerfile copies the custom plugins into the image.

> Note:  Uncomment `COPY kong.yml /etc/kong/kong.yml` in the Dockerfile to utilize the local kong.yml, otherwise it will pull from S3 and not include your configurations.  Also in the `docker-entrypoint.sh`, comment out the `aws` file copying and the `cd /opt/va` since that directory will not exist. 

Ensure you first build `docker build -t health-apis-kong:latest .` to test your changes.

`docker-compose up`

#### The Magical Way
1. Clone `health-apis-data-query-deployment` to this repo's parent directory, `../health-apis-data-query-deployment`
2. Create ./secrets.conf using variables defined for kong in the deployment unit.
   These values should *not* be encrypted
   See `../health-apis-data-query-deployment/lab.conf` as an example.
3. Run `./run-local.sh`

Notes:
- The Kong container application will be built using a `local` tag
- It will be started with AWS S3 configuration disabled
- It will generate a Kong configuration based on the Data Query deployment unit and volume mount
- It will expose ports `8000`, `8001`, `8443`, and `8444`

##### Disclaimer
The `run-local.sh` needs to know details about the platform your running on to properly configure Kong.
For example, to access locally running applications on Apple's OS X platform, the hostname of the services
must be `host.docker.internal`. If your platform is not currently supported by `run-local.sh`, it will
abort. But don't dispair, you make the script better by adding support for your OS.