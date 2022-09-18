#!/bin/sh -e

# REQUIRED ENVIRONMENT VARIABLES
# - KOJI_ADMIN_CERTIFICATE_KEY: path to a file containing the private key
if [ -z "$KOJI_ADMIN_CERTIFICATE_KEY" ]; then
    echo "\$KOJI_ADMIN_CERTIFICATE_KEY must be set"
    exit 1
fi
if [ ! -f "$KOJI_ADMIN_CERTIFICATE_KEY" ]; then
    echo "$KOJI_ADMIN_CERTIFICATE_KEY not present"
    exit 1
fi

# Create the cert plus private key used by the koji CLI
cat /etc/pki/koji/koji-admin.crt "$KOJI_ADMIN_CERTIFICATE_KEY" > /etc/pki/koji/koji-admin.pem

# Sleep forever. This will keep the container running so it can be attched to
# Running tail instead of a shell builtin like `sleep` allows the process to be killed
# so the container can be shutdown cleanly.
exec tail -f /dev/null
