#!/usr/bin/env bash
set -euo pipefail

IMAGE=vasdvp/health-apis-kong:$VERSION

echo "Building $IMAGE"

docker build -t $IMAGE .

if [ $RELEASE == true ]
then
  echo "Pushing $IMAGE"
  docker push $IMAGE
fi


echo "Removing local image"
docker rmi $IMAGE
