#!/bin/bash
source config.sh

# temporary files directory
mkdir -p $TMP_DIR
cd $TMP_DIR

# log output
log() {
  echo "> $@"
}

# suppress output
quiet() {
  $@ 2>&1 >/dev/null
}

# api call
api() {
  if [[ -z "${@:3}" ]]; then
    local data=
  else
    local data="-d ${@:3}"
  fi

  curl --silent -u "$HUBUSER:$HUBPASS" -X $1 https://api.github.com/$2 "$data"
}

# clean up string
clean() {
  stripped=$(cat - | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')

  escaped=${stripped//\'/\\\'}
  escaped=${stripped//\"/\\\"}

  echo $escaped
}

depend() {
  if ! hash $1 2>/dev/null; then
    echo "the command $1 doesn't exist"
    exit 1
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

  # fetch the old description from the api
  old_description=$(api GET repos/$HUBUSER/$repo | jq -r .description | clean)

  # initialize json with repo name
  json="{}"
  json=$(echo $json | jq ".name = \"$repo\"")

  # prefix description with prefix if it doesn't contain "mirror"
  if [[ "$old_description" != *"$MIRRORPREFIX"* ]]; then
    new_description=$MIRRORPREFIX$old_description

    json=$(echo $json | jq ".description = \"$new_description\"")
  fi

  # replace homepage with original repo url
  homepage=https://gitlab.com/$LABUSER/$repo
  json=$(echo $json | jq ".homepage = \"$homepage\"")

  # commit the repo metadata
  quiet api PATCH repos/$HUBUSER/$repo "$(echo $json)"

  # only clone if the mirror directory doesn't exist already
  if [ -d $repo.git ]; then
    quiet pushd $repo.git
    log "fetching repository $labrepo"
    git fetch -q --tags
  else
    log "cloning repository $labrepo"
    git clone --mirror $labrepo
    quiet pushd $repo.git

    log "added remote github: $hubrepo"
    git remote add github $hubrepo
  fi

  log "pushing to repository $hubrepo"
  git push --mirror $hubrepo
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
