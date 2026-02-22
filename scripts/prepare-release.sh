#!/bin/bash
set -e

# Semantic release preparation script
# Called by semantic-release to update the version in package.json

echo "Updating version in package.json to ${1}..."
sed -i "s/\"version\": \".*\"/\"version\": \"${1}\"/" package.json

echo "Version ${1} ready for release."
