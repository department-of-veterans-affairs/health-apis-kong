#!/usr/bin/env bash

cd $(dirname $0)

unsupportedOs() {
  cat<<EOF
Well... this is awkward, but I don't know how to work on your operating system.
Perhaps you can teach me. I need to the know the IP address or name of your
host system that is accessible from within docker containers.
EOF
  exit 1
}

case $(uname) in
  # https://docs.docker.com/docker-for-mac/networking/
  Darwin) HOST_ACCESSIBLE_FROM_WITHIN_DOCKER=host.docker.internal;;
  *) unsupportedOs;;
esac

DQ_DEPLOYMENT=$(find .. -name health-apis-data-query-deployment -type d | head -1)
[ -z "$DQ_DEPLOYMENT" ] && echo "Cannot find health-apis-data-query-deployment" && exit 1

SOURCE_CONF=$DQ_DEPLOYMENT/s3/kong/kong.yml
[ ! -f $SOURCE_CONF ] && echo "Cannot find $SOURCE_CONF" && exit 1

SECRETS=$(pwd)/secrets.conf
[ ! -f $SECRETS ] && echo "Cannot find $SECRETS" && exit 1

#
# We are going to stuff DEV_CONF into the docker container, but
# first we want to copy the configuration used in production from
# data-query. We'll need to provide values for the environment variables
# which includes secrets. We'll assume the user has a `secrets.conf`
# file locally (not committed to git)
#
# After we do environment substitution, we'll need to make a few changes
# to run with local applications.
#
DEV_CONF=$(pwd)/dev-kong.yaml

(
  echo "Loading $SECRETS"
  . $SECRETS
  cat $SOURCE_CONF | envsubst > $DEV_CONF
)
sed -i \
    -e "s/ids:8082/$HOST_ACCESSIBLE_FROM_WITHIN_DOCKER:8089/" \
    -e "s/data-query:80/$HOST_ACCESSIBLE_FROM_WITHIN_DOCKER:8090/" \
    $DEV_CONF

IMAGE_NAME=health-api-kong:local
docker build -t $IMAGE_NAME .

docker run \
  --rm \
  -it \
  -e "KONG_ADMIN_ACCESS_LOG=/dev/stdout" \
  -e "KONG_ADMIN_ERROR_LOG=/dev/stderr" \
  -e "KONG_ADMIN_LISTEN=0.0.0.0:8001" \
  -e "KONG_DATABASE=off"\
  -e "KONG_DECLARATIVE_CONFIG=/etc/kong/kong.yml" \
  -e "KONG_LOG_LEVEL=debug" \
  -e "KONG_PROXY_ACCESS_LOG=/dev/stdout" \
  -e "KONG_PROXY_ERROR_LOG=/dev/stderr"\
  -e "KONG_PLUGINS=request-termination,response-transformer,health-apis-token-validator,health-apis-static-token-handler,health-apis-patient-registration" \
  -e "AWS_BUCKET_NAME=unused" \
  -e "AWS_CONFIG_FOLDER=unused" \
  -e "AWS_APP_NAME=kong" \
  -v "$DEV_CONF:/etc/kong/kong.yml" \
  -p 8000:8000 \
  -p 8001:8001 \
  -p 8443:8443 \
  -p 8444:8444 \
  $IMAGE_NAME
