#!/bin/bash
export image=$(jq -r '.image.repository' build/package.json)
export description=$(jq -r '.description' build/package.json)
export platforms=$(jq -r '.image.platforms | join(",")' build/package.json)
export version={version}
# If vars have no value, exit with status code 1
if [ -z "$image" ]; then echo "No image name." && exit 1; fi
if [ -z "$description" ]; then echo "No description." && exit 1; fi
if [ -z "$platforms" ]; then echo "No platforms." && exit 1; fi
if [ -z "$version" ]; then echo "No version." && exit 1; fi