#!/bin/sh -e

# REQUIRED ENVIRONMENT VARIABLES
# - DIST_GIT_CERTIFICATE_FILE: path to the private key for the certificate
if [ -z "$DIST_GIT_CERTIFICATE_KEY" ]; then
    echo "\$DIST_GIT_CERTIFICATE_KEY must be set"
    exit 1
fi
if [ ! -f "$DIST_GIT_CERTIFICATE_KEY" ]; then
    echo "$DIST_GIT_CERTIFICATE_KEY not present"
    exit 1
fi

cp "$DIST_GIT_CERTIFICATE_KEY" /etc/pki/koji/dist-git.key

exec /usr/sbin/httpd -DFOREGROUND
