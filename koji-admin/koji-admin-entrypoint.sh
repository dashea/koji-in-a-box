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

# koji userinfo exits with status 0 when it successfully determines no user exists.
# Capture the exit status to determine if the command was able to reach the koji-hub or
# not, and capture the output to look for the "No such user" string.
# LANG=C ensures the string isn't localized.
user_exists()
{
    if [ -z "$1" ]; then
        echo "User argument missing"
        exit 1
    fi

    set +e
    output="$(env LANG=C koji userinfo "$1" 2>&1)"
    exitcode="$?"
    set -e

    if [ "$exitcode" -ne 0 ]; then
        echo "Error running koji userinfo: $output"
        exit 1
    fi

    if echo "$output" | grep -q '^No such user:'; then
        return 1
    else
        return 0
    fi
}

# Create the cert plus private key used by the koji CLI
cat /etc/pki/koji/koji-admin.crt "$KOJI_ADMIN_CERTIFICATE_KEY" > /etc/pki/koji/koji-admin.pem

# Create requested users
# There's not a great way to test if users exist or not (koji userinfo always exists with status 0), so just always attempt to add and ignore errors
for user in $KOJI_ADMIN_ADD_USERS ; do
    user_exists "$user" || koji add-user "$user"
done

# Sleep forever. This will keep the container running so it can be attched to
# Running tail instead of a shell builtin like `sleep` allows the process to be killed
# so the container can be shutdown cleanly.
exec tail -f /dev/null
