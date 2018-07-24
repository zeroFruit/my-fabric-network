#!/usr/bin/env bash

set -e

SDIR=$(dirname "$0")
source ${SDIR}/clean.sh

cd ${SDIR}

# Create docker-compose file
${SDIR}/makeDocker.sh

# Create the docker containers
log "Creating docker containers ..."
docker-compose up -d
