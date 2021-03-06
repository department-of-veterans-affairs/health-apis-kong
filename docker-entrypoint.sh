#!/bin/sh
set -e

# https://github.com/department-of-veterans-affairs/health-apis-devops/blob/master/operations/application-base/entrypoint.sh#L6-L27
# Get files off s3 bucket
#
if [ "$AWS_CONFIG_FOLDER" == unused ]
then
  echo "Skipping AWS based configuration"
  mkdir -p /opt/va && touch /opt/va/test.tmp
  touch /etc/kong/test.tmp
else
  echo "Loading AWS based configuration"
  [ -z "$AWS_CONFIG_FOLDER" ] && AWS_CONFIG_FOLDER=$AWS_APP_NAME
  aws s3 cp s3://$AWS_BUCKET_NAME/$AWS_APP_NAME/ /opt/va/ --recursive

  # Copies kong.yml configuration from S3
  # Includes plugin configurations that cannot be commited to github
  # For local development, consider commenting out this line and instead
  # uncommenting the Dockerfile line - COPY kong.yml /etc/kong/kong.yml
  aws s3 cp s3://$AWS_BUCKET_NAME/$AWS_CONFIG_FOLDER_KONG/ /etc/kong/ --recursive
fi

#
# Start up app and log activity
# If a start up hook exists, execute it
#
if [ -d /opt/va ]
then
  cd /opt/va/
  HOOK=on-start.sh
  if [ -f $HOOK ]
  then
    echo ============================================================
    echo "Running start up HOOK"
    chmod +x $HOOK
    ./$HOOK
    HOOK_STATUS=$?
    [ $HOOK_STATUS != 0 ] && echo "Start up hook failed with status $HOOK_STATUS" && exit 1
  fi
fi

#################################################################################
# Base Kong Entrypoint script
#################################################################################

export KONG_NGINX_DAEMON=off

has_transparent() {
  echo "$1" | grep -E "[^\s,]+\s+transparent\b" >/dev/null
}

if [[ "$1" == "kong" ]]; then
  PREFIX=${KONG_PREFIX:=/usr/local/kong}

  if [[ "$2" == "docker-start" ]]; then
    shift 2
    kong prepare -p "$PREFIX" "$@"
    
    # workaround for https://github.com/moby/moby/issues/31243
    chmod o+w /proc/self/fd/1 || true
    chmod o+w /proc/self/fd/2 || true

    if [ "$(id -u)" != "0" ]; then
      exec /usr/local/openresty/nginx/sbin/nginx \
        -p "$PREFIX" \
        -c nginx.conf
    else
      if [ ! -z ${SET_CAP_NET_RAW} ] \
          || has_transparent "$KONG_STREAM_LISTEN" \
          || has_transparent "$KONG_PROXY_LISTEN" \
          || has_transparent "$KONG_ADMIN_LISTEN";
      then
        setcap cap_net_raw=+ep /usr/local/openresty/nginx/sbin/nginx
      fi
      chown -R kong:0 /usr/local/kong
      exec su-exec kong /usr/local/openresty/nginx/sbin/nginx \
        -p "$PREFIX" \
        -c nginx.conf
    fi
  fi
fi

exec "$@"
