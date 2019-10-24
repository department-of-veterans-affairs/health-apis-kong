# health-apis-kong

This project provides a customized Kong image that adds custom plugins as well
as an `on-start.sh` script from AWS S3.

### AWS S3 backed start up
When the Health APIs Kong image starts. If the AWS environment variables are
specified, configuration will be pulled from the S3 bucket and applied kong.
If a special file `on-start.sh` is available in the S3 bucket and folder, this
script will be executed _prior_ to launching Kong. This script can be used to
customize Kong.

## Plugin: health-apis-token-validator

A Kong plugin to validate a supplied OAuth token.  It can be installed on a Kong
instance and configured to run against the entire instance, specific API's, or
specific routes. This plugin also specifies the header `X-VA-ICN` to ICN of the
patient making the request.

#### Configuration
```
verification_url - The OAuth token validation URL
verification_timeout - How long to wait in milliseconds while verifying
verification_host - The value of the Host header to send while verifying token
static_token - The value of the static test token
static_icn - The ICN that is associated with the test patient
api_key - OAuth API key
```

Advanced test usage
```
custom_scope_validation_enabled - If true, custom scopes will be used instead of those provided in the OAuth request
custom_scope - The resource name of the custom scope used to override normal scope processing
```

---

## Plugin: health-apis-static-token-handler
This plugin enables static token support to the OAuth token exchange flow.
This plugin is generally applied to it's own route, e.g. `/token` and provided
as the OAuth token exchange endpoint.

This plugin works in conjunction with `health-apis-token-validator`. Together,
these plugins allow access to single configured test patient that avoid normal
OAuth flow by allowing test machinery to be pre-configured with a predetermined
test access code.


```
static_refresh_token - The OAuth refresh token for the static test patient
static_access_token - The OAuth access token for the static test patient
static_expiration - Age before static token expires
static_icn - The test patient ICN associated with the static token
static_scopes - OAuth scopes applied to the static token
```

---

## Plugin: health-apis-patient-registration

This Kong plugin serves two purposes.
1. Handle patient registration with the Identity Service as part of the access
   token retrieval. This can be disabled in the plugin configuration, set
   `register_patient = false`.
2. Implement a work around to limitations with the Okta OAuth server that is
   rejected Access token requests to `/token` where the `client_id` and
   `client_secret` are passed as a Basic Authentication header. This work
   around will convert the `Authorization` header in to a client credentials i
   n the post body.

```
register_patient - (`true`|`false`) Indicates whether registration is enabled.
ids_url - The URL of the identity service
token_url - The URL of the OAuth token exchange endpoint
token_timeout - Number of milliseconds to wait while exchanging the token
static_refresh_token - The OAuth refresh token for the static test patient
static_icn - The test patient ICN associated with the static token
```

> Note:  The static patient still needs to register with the Identity Service.

---
## Plugin: health-apis-doppelganger

This plugin allows requests for one user be swapped with results from a test user.
It is used to allow developers with ID.me accounts but no VA records be swapped to
allow access to test data.
This plugin will replace known 'doppelganger' ICNs (typically ICNs of developers or
support staff) in incomming HTTP requests with a known test patient user
Responses will reverse the translation so that links or ICNs in the response
can be presented in terms of the original request.

An example:
I am a developer with an ID.me account but no records at the VA. My ICN is 999.
This plugin is configured such that 999 is a registered doppelganger for test
patient 123. Using the Apple Health app, I make a request for /Condition?patient=999
This plugin will request Condition?patient=123 instead. Just prior to returning the
response,  all occurrences of patient 123 are replaced with 999 to allow links
to continue to work.

##### WARNING
This plugin assumes that ICNs are unique enough to not naturally occur in text.
For example, the ICN 1017283132V631076 is easily recogized and replaced with
1011537977V693883 using simple string replacement techniques.

```
target_icn - the target test patient ICN
doppelgangers - array of developer ICNs that are considered doppelganges of the
target_icn test patient
```


---
## Plugin: health-apis-patient-matching

This plugin will perform patient-matching validation on all downstream responses. (data-query, etc...) The plugin runs in the priority chain at priority 805, immediately
after doppelganger but before the response transformer.

The health-apis-patient-matching plugin will act as follows on any 200 series downstream response.
(We fail through on non-200s)

The plugin requires two headers,
  Request header `X-VA-ICN`- the client ICN provided internally by the health-apis-token-validator plugin.
  Response header `X-VA-INCLUDES-ICN` - a comma seperated string of icn's who's data is contained in the payload. This is provided, along with the payload, by the downstream service, e.g. data-query

NOTE: The `XA-VA-INCLUDES-ICN` response header supports a comma delimited list of ICNs in anticipation of system use cases, e.g. clinician workflows. So that service implementations may develop in advance of this plugin. At this time, the plugin only validates the single ICN uses cases needed for patient-centric access.


The health-apis-patient-matching plugin uses the following rules, in order:

1. `X-VA-INCLUDES-ICN` is empty or missing, we 403 forbidden.
2. `X-VA-INCLUDES-ICN` is "NONE" we know the payload is patient agnostic (empty bundle, medication, etc...) and will allow the response through
3. `X-VA-ICN` is missing, we 403 forbidden. We don't know the clients icn. Something spooky happened.
4. `X-VA-ICN` does not match exactly the ICN value in the `X-VA-INCLUDES-ICN` we return 403 forbidden.
5. `X-VA-ICN` matches exactly `X-VA-INCLUDES-ICN`

### NOTE:
The health-apis-patient-matching plugin currently supports only an exact match of `X-VA-ICN` to `X-VA-INCLUDES-ICN`. This is overly protective in the case of larger scale clinician workflows, etc... Once these have a more concrete implementation/plan, this plugin will need to be revisted.


##### WARNING
The health-apis-token-protected-operation plugin assumes that ICNs are unique enough to not naturally occur in text.
For example, the ICN 1017283132V631076 is easily recogized and replaced with
1011537977V693883 using simple string replacement techniques.

```
target_icn - the target test patient ICN
doppelgangers - array of developer ICNs that are considered doppelganges of the
target_icn test patient
```

## Plugin: health-apis-token-protected-operation

This plugin allows the addition of headers that, when added, are validated using
a list of accepted tokens. The plugin allows for either sending the header and
token along, or for sending the application a separate boolean header value based
on whether or not the token was in the list of valid tokens. While validating the
header value, this plugin also has an option to allow the header through regardless
of token validity (can map to a different operation in the application.)

An example:
In the case of returning raw results, we want to allow only certain users to get
records back. Therefore, a configuration would use the header 'raw' with a token
to validate the user is allowed access to raw data. For a raw response, we want
to pass the application a boolean to check for, not the full token, so the
send_boolean_header configuration would be set to something like 'rawAppHeader' so
that the application can use that value instead of the 'raw' header that contains
the token value. Finally, if the token is invalid, we don't want to send back a
401 with an operation outcome, so we can set sends_unauthorized to false and
write code in the application to send back a regular fhir compliant response
when the token is invalid.

#### Configuration
```
request_header_key - (required) The name of the header that kong should expect
  to see in the request (i.e. raw)
allowed_tokens - (required) An array of allowed token values (should have
  comments as to who uses each token)
send_boolean_header - The header that kong should send to the application
  (If this field is not provided, the plugin assumes request_header_key is the
    only needed value and passes it along to the application with the token.)
allow_empty_header - Boolean that if set to true, will allow requests
  if the header is missing. This can be useful for situations where the header
  can be used to trigger additional behavior, but it is still valid to request
  with out it. (Defaults to false)
```

---
### Example

```
plugins:
 - name: health-apis-doppelganger
   config:
     target_icn: 111222333V000999
     doppelgangers:
     - "1028283132V7777777"
     - "1013283132V8888888"
     - "1017284442V9999999"
 - name: health-apis-token-validator
   config:
     verification_url: https://dev-api.va.gov/internal/auth/v0/validation
     verification_timeout: 10000
     api_key: ABC123
     static_token: 5@t1C
     static_icn: 111222333V000999
- name: argonaut-token-route
 paths:
 - /token
 strip_path: false
 plugins:
 - name: health-apis-static-token-handler
   config:
     static_refresh_token: r3fr35H
     static_access_token: 5@t1C
     static_expiration: 3599
     static_icn: 111222333V000999
     static_scopes: "launch/patient offline_access patient/Patient.read patient/Medication.read patient/Condition.read patient/Immunization.read patient/AllergyIntolerance.read patient/MedicationOrder.read patient/MedicationStatement.read patient/Procedure.read patient/Observation.read patient/DiagnosticReport.read patient/Encounter.read patient/Location.read"
 - name: health-apis-patient-registration
   config:
     register_patient: false
     ids_url: http://ids:8089/api/v1/ids
     token_url: https://dev-api.va.gov/oauth2/token
     token_timeout: 10000
     static_refresh_token: r3fr35H
  - name: health-apis-token-protected-operation
    config:
      request_header_key: protectedOp
      allowed_tokens: ["orange", "shanktopus"]
      application_header_key: appHeader
      sends_unauthorized: false
      allow_if_header_is_missing: false
```

---

## Local development

1. Clone `health-apis-data-query-deployment` to this repo's parent directory, `../health-apis-data-query-deployment`
2. Create ./secrets.conf using variables defined for kong in the deployment unit.
   These values should *not* be encrypted. See example below.
3. Run `./run-local.sh`


Notes:
- The Kong container application will be built using a `local` tag
- It will be started with AWS S3 configuration disabled
- It will generate a Kong configuration based on the Data Query deployment unit and volume mount
- It will expose ports `8000`, `8001`, `8443`, and `8444`

---

#### Example Generating `secrets.conf`
The lab configuration makes a good starting point as an example since it allows connectivity to the
Mitre database.

```
pushd ../../health-apis-data-query-deployment
../health-apis-deployer/toolkit/dtk decrypt
popd
grep " KONG_" ../health-apis-data-query-deployment/lab.conf > secrets.conf
```


---
#### Disclaimer
The `run-local.sh` needs to know details about the platform your running on to properly configure Kong.
For example, to access locally running applications on Apple's OS X platform, the hostname of the services
must be `host.docker.internal`. If your platform is not currently supported by `run-local.sh`, it will
abort. But don't dispair, you make the script better by adding support for your OS.
