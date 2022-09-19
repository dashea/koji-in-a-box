#!/bin/sh -e

# REQUIRED ENVIRONMENT VARIABLES
# - KOJI_BUILDER_CERTIFICATE_KEY: path to a file containing the arch-specific private key
# - KOJI_BUILDER_PROBE_CERTIFICATE_KEY: path to a file containing the shared "probe" private key
# - ARCH: architecture, saved from the $arch build argument
if [ -z "$KOJI_BUILDER_CERTIFICATE_KEY" ]; then
    echo "\$KOJI_BUILDER_CERTIFICATE_KEY must be set"
    exit 1
fi
if [ ! -f "$KOJI_BUILDER_CERTIFICATE_KEY" ]; then
    echo "$KOJI_BUILDER_CERTIFICATE_KEY not present"
    exit 1
fi

if [ -z "$KOJI_BUILDER_PROBE_CERTIFICATE_KEY" ]; then
    echo "\$KOJI_BUILDER_PROBE_CERTIFICATE_KEY must be set"
    exit 1
fi
if [ ! -f "$KOJI_BUILDER_PROBE_CERTIFICATE_KEY" ]; then
    echo "$KOJI_BUILDER_PROBE_CERTIFICATE_KEY not present"
    exit 1
fi

if [ -z "$ARCH" ]; then
    echo "\$ARCH must be set"
    exit 1
fi

cat /etc/pki/koji/koji-builder.crt "$KOJI_BUILDER_CERTIFICATE_KEY" > /etc/pki/koji/koji-builder.pem
cat /etc/pki/koji/koji-builder-probe.crt "$KOJI_BUILDER_PROBE_CERTIFICATE_KEY" > /etc/pki/koji/koji-builder-probe.pem

# This part is extremely stupid
# If kojid connects to the hub before associated username has been added as a host,
# the kojid username is automatically added as a regular user. This prevents the user from
# being added as a host, and it cannot be undone. Before starting kojid, use a non-admin,
# non-builder user shared by all of the builders to test whether or not this specific builder
# has been added to the database yet or not.
hostname="koji-builder-$ARCH"
host_ready()
{
    if koji -p local-koji hostinfo "$hostname" >/dev/null 2>&1 ; then
        return 0
    else
        return 1
    fi
}

until host_ready ; do
    echo "$hostname not yet added to build hosts..."
    sleep 5
done

exec /usr/sbin/kojid --fg --force-lock
