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
 --bulk                        Alias: -d health-apis-bulk-fhir-deployment
 --debug                       Enable debugging output
 --dq                          Alias: -d health-apis-data-query-deployment
 -d, --deployment-unit <name>  Specify the deployment unit name
 -h, --help                    Display this help and exit
 -y, --yaml <file>             Use this Kong configuration file
$1
EOF
  exit 1
}


USE_THIS_YAML=
DU_NAME=

ARGS=$(getopt -n $(basename ${0}) \
    -l "debug,help,deplyment-unit:,dq,bulk,yaml:" \
    -o "hd:y:" -- "$@")
[ $? != 0 ] && usage
eval set -- "$ARGS"
while true
do
  case "$1" in
    --debug) set -x;;
    -h|--help) usage "halp! what this do?";;
    -y|--yaml) USE_THIS_YAML="$2";;
    -d|--deplyment-unit) [[ "$2" =~ health-apis-.*-deployment ]] && DU_NAME="$2" || DU_NAME="health-apis-$2-deployment";;
    --dq) DU_NAME=health-apis-data-query-deployment;;
    --bulk) DU_NAME=health-apis-bulk-fhir-deployment;;
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
  #
  # I wish this didn't know about server/port mappings...
  #
  sed -i \
      -e "s/ids:8082/$HOST_ACCESSIBLE_FROM_WITHIN_DOCKER:8089/" \
      -e "s/data-query:80/$HOST_ACCESSIBLE_FROM_WITHIN_DOCKER:8090/" \
      -e "s/incredible-bulk:80/$HOST_ACCESSIBLE_FROM_WITHIN_DOCKER:8091/" \
      $DEV_CONF
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
docker build -t $IMAGE_NAME .

PLUGIN_ARRAY=('request-termination' 'response-transformer' \
  'health-apis-token-validator' 'health-apis-static-token-handler' \
  'health-apis-patient-registration' 'health-apis-doppelganger' \
  'health-apis-token-protected-operation' 'health-apis-patient-matching' \
  'request-transformer')

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
