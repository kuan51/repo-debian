#!/bin/bash

# Source vars
. build/vars.sh

prod={prod}
if [ $prod == false ]; then 
    version=${version}_beta
fi

echo "Chosen Platforms: $platforms"
echo "Chosen Tag: $image:$version"

docker buildx build \
  --push \
  --provenance false \
  --platform $platforms \
  --tag $image:$version \
  --tag $image:latest \
  --build-arg DESCRIPTION="$description" \
  --file ./Dockerfile .