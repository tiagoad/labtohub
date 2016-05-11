#!/bin/bash

# defaults
GIT_COMMAND="git"
DELETE_WORKSPACE="ON"

# import config
source config.sh

# temporary files directory
mkdir -p $TMP_DIR
cd $TMP_DIR

# log output
log() {
  if [[ "$QUIET" != "ON" ]]; then
    echo "$@"
  fi
}

# error output
error() {
  echo "$@" >&2
}

# suppress output
quiet() {
  $@ 2>/dev/null >/dev/null
}

# api call
api() {
  if [[ -z "${@:3}" ]]; then
    local data=
  else
    local data="-d ${@:3}"
  fi

  curl --silent -u "$HUBUSER:$HUBPASS" -X $1 https://api.github.com$2 "$data"
}

# clean up string
clean() {
  stripped=$(cat - | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')

  escaped=${stripped//\'/\\\'}
  escaped=${stripped//\"/\\\"}

  echo $escaped
}

# dependency "management"
depend() {
  if ! hash $1 2>/dev/null; then
    error "the command $1 doesn't exist"
    exit 1
  fi
}

# run git command
git_run() {
  export GIT_ASKPASS=echo

  if [[ "$QUIET" == "ON" && "$1" != "remote" ]]; then
    git $@ --quiet
  else
    git $@
  fi
}

# dependencies
depend curl
depend jq

for repo in ${LABREPOS[@]}; do
  log $repo
  log =============
  hubrepo=git@github.com:$HUBUSER/$repo.git
  labrepo=https://gitlab.com/$LABUSER/$repo.git

  # get the repo info from the api
  repo_json=$(api GET /repos/$HUBUSER/$repo)

  # initialize json with repo name
  json="{}"
  json=$(echo $json | jq ".name = \"$repo\"")

  # replace homepage with original repo url
  homepage=https://gitlab.com/$LABUSER/$repo
  json=$(echo $json | jq ".homepage = \"$homepage\"")

  # create the repo if it doesn't exist
  if [[ $(echo $repo_json | jq -r .message) == "Not Found" ]]; then
    json=$(echo $json | jq ".description = \"$MIRRORPREFIX\"")

    log "creating repo $repo on github"
    quiet api POST /user/repos "$(echo $json)"
  # if it exists then change the description and stuff
  else
    old_description=$(echo $repo_json | jq -r .description | clean)

    # prefix description with prefix if it doesn't contain "mirror"
    if [[ "$old_description" != *"$MIRRORPREFIX"* ]]; then
      new_description=$MIRRORPREFIX$old_description

      json=$(echo $json | jq ".description = \"$new_description\"")
    fi

    quiet api PATCH /repos/$HUBUSER/$repo "$(echo $json)"
  fi

  # only clone if the mirror directory doesn't exist already
  if [ -d $repo.git ]; then
    quiet pushd $repo.git
    log "fetching repository $labrepo"
    git_run fetch -q --tags
  else
    log "cloning repository $labrepo"
    git_run clone --mirror $labrepo
    quiet pushd $repo.git

    log "added remote github: $hubrepo"
    git_run remote add github $hubrepo
  fi

  log "pushing to repository $hubrepo"
  git_run push --mirror $hubrepo
  quiet popd

  if [[ "$DELETE_WORKSPACE" == "ON" ]]; then
    log "removing $repo.git"
    rm -rf "$repo.git"
  fi
done

if [[ "$DELETE_WORKSPACE" == "ON" ]]; then
  log "removing temp directory"
  rm -rf $TMP_DIR
fi
