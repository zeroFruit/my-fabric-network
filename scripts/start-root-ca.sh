#!/bin/bash

set -e

fabric-ca-server init -b $BOOTSTRAP_USER_PASS

cp $FABRIC_CA_SERVER_HOME/ca-cert.pem $TARGET_CERTFILE

# Add the custom orgs
for o in $FABRIC_ORGS; do
   aff=$aff"\n   $o: []"
done
aff="${aff#\\n   }"
sed -i "/affiliations:/a \\   $aff" \
   $FABRIC_CA_SERVER_HOME/fabric-ca-server-config.yaml

# Start the root CA
fabric-ca-server start