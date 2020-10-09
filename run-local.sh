#!/usr/bin/env bash

#
# This script will
#

cd $(dirname $0)


#============================================================
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
  Linux) HOST_ACCESSIBLE_FROM_WITHIN_DOCKER=172.17.0.1;;
  *) unsupportedOs;;
esac
#============================================================


usage() {
cat<<EOF

$0 [options]

Build and run Kong locally.
- Create a kong configuration based on an existing kong deployment
  unit configuration. It will substitue values found in ./secrets.conf.
  Do not encrypt secrets.conf
- Build the Kong container with a `local` tag
- Run the `local` Kong container using the generated kong configuration

Options:
 --bulk                        Alias: -d health-apis-bulk-fhir-deployment -m ...
 --debug                       Enable debugging output
 --dq                          Alias: -d health-apis-data-query-deployment -m ...
 --fr                          Alias: -d health-apis-fall-risk-deployment -m ...
 -d, --deployment-unit <name>  Specify the deployment unit name
 -h, --help                    Display this help and exit
 -m, --map-server <spec>       Map a service to the local host
 -y, --yaml <file>             Use this Kong configuration file
 --yolo                        Build faster with more risk using a cache

Server Mapping
The --map-server option allows you to map a hostname and port to a port on your local host.
The specification is 'host:port:localPort'. The "localhost" is OS aware and will adapt to
Docker for Mac or Linux.

Example

$0 -d health-apis-fall-risk-deployment -m fall-risk:80:8070


$1
EOF
  exit 1
}


USE_THIS_YAML=
DU_NAME=
SERVER_MAPPINGS=
CACHE_OPT="--no-cache"

ARGS=$(getopt -n $(basename ${0}) \
    -l "debug,help,deplyment-unit:,dq,bulk,fr,facilities,yaml:,map-server:,yolo" \
    -o "hd:y:m:" -- "$@")
[ $? != 0 ] && usage
eval set -- "$ARGS"
while true
do
  case "$1" in
    --debug) set -x;;
    -h|--help) usage "halp! what this do?";;
    -y|--yaml) USE_THIS_YAML="$2";;
    --yolo) CACHE_OPT="";;
    -d|--deplyment-unit) [[ "$2" =~ health-apis-.*-deployment ]] && DU_NAME="$2" || DU_NAME="health-apis-$2-deployment";;
    --dq) DU_NAME=health-apis-data-query-deployment; SERVER_MAPPINGS="data-query:80:8090 ids:8082:8089";;
    --bulk) DU_NAME=health-apis-bulk-fhir-deployment; SERVER_MAPPINGS="incredible-bulk:80:8091";;
    --fr) DU_NAME=health-apis-fall-risk-deployment; SERVER_MAPPINGS="fall-risk:80:8070";;
    --facilities) DU_NAME=lighthouse-facilities-deployment; SERVER_MAPPINGS="facilities:8082:8085 facilities-collector:8082:8080";;
    -m|--map-server) SERVER_MAPPINGS+="$2 ";;
    --) shift;break;;
  esac
  shift;
done


copyConfFromDeployment() {
  [ -z "$DU_NAME" ] && usage "Deployment unit not specified"
  DU_DEPLOYMENT=$(find .. -name $DU_NAME -type d | head -1)
  [ ! -d $DU_DEPLOYMENT ] && echo "Cannot find $DU_NAME in $(readlink -f ..)" && exit 1

  SOURCE_CONF=$DU_DEPLOYMENT/s3/kong/kong.yml
  [ ! -f $SOURCE_CONF ] && echo "Cannot find $DU_DEPLOYMENT/s3/kong/kong.yml" && exit 1

  SECRETS=$(pwd)/secrets.conf
  [ ! -f $SECRETS ] && echo "Cannot find $SECRETS" && exit 1

  DEV_CONF=$(pwd)/dev-kong.yaml
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
  (
    echo "Loading $SECRETS"
    . $SECRETS
    echo "Writing $DEV_CONF"
    cat $SOURCE_CONF | envsubst > $DEV_CONF
  )

  for mapping in $SERVER_MAPPINGS
  do
    local from=${mapping%:*}
    local toPort=${mapping##*:}
    sed -i "s/$from/$HOST_ACCESSIBLE_FROM_WITHIN_DOCKER:$toPort/" $DEV_CONF
  done
}


useSpecifiedYaml() {
  DEV_CONF=$(readlink -f $USE_THIS_YAML)
  echo "Using $DEV_CONF"
}

if [ -n "$USE_THIS_YAML" ]
then
  useSpecifiedYaml
elif [ -n "$DU_NAME" ]
then
  copyConfFromDeployment
fi


[ -z "$DEV_CONF" ] && usage "You must specify --yaml or --deployment-unit"

IMAGE_NAME=health-api-kong:local
docker build $CACHE_OPT -t $IMAGE_NAME .

[ "$?" != 0 ] && exit 1

PLUGIN_ARRAY=('request-termination' 'response-transformer' \
  'health-apis-token-validator' 'health-apis-static-token-handler' \
  'health-apis-patient-registration' 'health-apis-doppelganger' \
  'health-apis-token-protected-operation' 'health-apis-patient-matching' \
  'request-transformer' 'lighthouse-fhir-post-based-searching')

docker run \
  --rm \
  -it \
  -e "KONG_ADMIN_ACCESS_LOG=/dev/stdout" \
  -e "KONG_ADMIN_ERROR_LOG=/dev/stderr" \
  -e "KONG_ADMIN_LISTEN=0.0.0.0:8001" \
  -e "KONG_DATABASE=off"\
  -e "KONG_DECLARATIVE_CONFIG=/etc/kong/kong.yml" \
  -e "KONG_LOG_LEVEL=info" \
  -e "KONG_PROXY_ACCESS_LOG=/dev/stdout" \
  -e "KONG_PROXY_ERROR_LOG=/dev/stderr"\
  -e "KONG_PLUGINS=$(echo ${PLUGIN_ARRAY[@]} | sed 's/ /,/g')" \
  -e "AWS_BUCKET_NAME=unused" \
  -e "AWS_CONFIG_FOLDER=unused" \
  -e "AWS_APP_NAME=kong" \
  -v "$DEV_CONF:/etc/kong/kong.yml" \
  -p 8000:8000 \
  -p 8001:8001 \
  -p 8443:8443 \
  -p 8444:8444 \
  $IMAGE_NAME
