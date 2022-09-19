#!/bin/sh -e

# REQUIRED ENVIRONMENT VARIABLES
# - KOJIRA_CERTIFICATE_KEY: path to the private key file
if [ -z "$KOJIRA_CERTIFICATE_KEY" ]; then
    echo "\$KOJIRA_CERTIFICATE_KEY must be set"
    exit 1
fi
if [ ! -f "$KOJIRA_CERTIFICATE_KEY" ]; then
    echo "$KOJIRA_CERTIFICATE_KEY not present"
    exit 1
fi

cat /etc/pki/koji/kojira.crt "$KOJIRA_CERTIFICATE_KEY" > /etc/pki/koji/kojira.pem

exec /usr/sbin/kojira --fg --force-lock
