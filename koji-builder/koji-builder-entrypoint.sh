#!/bin/sh -e

# REQUIRED ENVIRONMENT VARIABLES
# - KOJI_BUILDER_CERTIFICATE_KEY: path to a file containing the arch-specific private key
if [ -z "$KOJI_BUILDER_CERTIFICATE_KEY" ]; then
    echo "\$KOJI_BUILDER_CERTIFICATE_KEY must be set"
    exit 1
fi
if [ ! -f "$KOJI_BUILDER_CERTIFICATE_KEY" ]; then
    echo "$KOJI_BUILDER_CERTIFICATE_KEY not present"
    exit 1
fi

cat /etc/pki/koji/koji-builder.crt "$KOJI_BUILDER_CERTIFICATE_KEY" > /etc/pki/koji/koji-builder.pem

exec /usr/sbin/kojid --fg --force-lock
