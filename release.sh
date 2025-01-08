#!/usr/bin/env bash

set -e

REPOSITORY_URL='http://0.0.0.0:8080'

VERSION_PY='yfinance/version.py'
GIT_BRANCH="$(git rev-parse --abbrev-ref HEAD)"
VERSION="$(sed -n 's/^version = "\([^"]*\)".*/\1/p' "./$VERSION_PY")"
BUILD_METADATA="$(date +%Y%m%d).$(( $(date "+10#%H * 60 + 10#%M") ))"
PRE_RELEASE_ID="pe${GIT_BRANCH}"
RELEASE_SEMVER="${VERSION}-${PRE_RELEASE_ID}+${BUILD_METADATA}"
echo "Release SemVersion: $RELEASE_SEMVER"

# Function to escape special characters for sed
escape_sed() {
  echo "$1" | sed 's/[&/\]/\\&/g'
}

function swap_version() {
  echo "Swapping version $1 for $2" && \
  sed -i "s/^version = \"$1\"/version = \"$2\"/" "$VERSION_PY"
}

function get_pypi_secret(){
  kubectl get secrets pypisecret --output=json | \
  jq -rc '.metadata.annotations[]' | \
  jq -rc '.stringData | "\(.username) \(.password)"'
}

function twine_upload() {
  read -r PYPI_USERNAME PYPI_PASSWORD <<<"$(get_pypi_secret)" && \
  twine upload \
    --verbose \
    "--repository-url=$REPOSITORY_URL" \
    "--username=$PYPI_USERNAME" \
    "--password=$PYPI_PASSWORD" \
    dist/*
}

function git_tag() {
  echo "Pushing git tags for $RELEASE_SEMVER" && \
  git tag -a "$RELEASE_SEMVER" && \
  git push origin "$RELEASE_SEMVER"
}

function dist_upload() {
  echo "Installing $RELEASE_SEMVER for upload" && \
  ESCAPED_VERSION=$(escape_sed "$VERSION") && \
  ESCAPED_RELEASE_SEMVER=$(escape_sed "$RELEASE_SEMVER") && \
  echo "Replacing $VERSION_PY" && \
  swap_version "$ESCAPED_VERSION" "$ESCAPED_RELEASE_SEMVER" && \
  cat "$VERSION_PY" && \
  echo "Running setup sdist..." && \
  python setup.py sdist bdist_wheel && \
  echo "Running twine upload..." && \
  twine_upload && \
  swap_version "$ESCAPED_RELEASE_SEMVER" "$ESCAPED_VERSION" && \
  echo "Reverted $VERSION_PY" && \
  cat "$VERSION_PY"
}

git_tag && dist_upload
