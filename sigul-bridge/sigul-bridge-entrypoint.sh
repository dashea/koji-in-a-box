#!/bin/sh -e

# REQUIRED ENVIRONMENT VARIABLE
# - SIGUL_BRIDGE_CERTIFICATE_KEY: path to the certificate key
if [ -z "$SIGUL_BRIDGE_CERTIFICATE_KEY" ]; then
    echo "\$SIGUL_BRIDGE_CERTIFICATE_KEY must be set"
    exit 1
fi
if [ ! -f "$SIGUL_BRIDGE_CERTIFICATE_KEY" ]; then
    echo "$SIGUL_BRIDGE_CERTIFICATE_KEY not present"
    exit 1
fi

# Initialize the certificate database
# Remove the directory first in case this is a restart, certutil will hang waiting for
# a password if a database already exists
rm -rf /var/lib/sigul
mkdir /var/lib/sigul
certutil -d /var/lib/sigul -N --empty-password

# Add the CA certificate
certutil -d /var/lib/sigul -A -n koji_ca_cert -t CT,, -a -i /etc/pki/koji/koji_ca_cert.crt

# Add the client certificate
cat /etc/pki/koji/sigul-bridge.crt "$SIGUL_BRIDGE_CERTIFICATE_KEY" > /etc/pki/koji/sigul-bridge.pem
openssl pkcs12 -export -in /etc/pki/koji/sigul-bridge.pem -out /etc/pki/koji/sigul-bridge.p12 -name sigul-bridge-cert -passout 'pass:'
pk12util -d /var/lib/sigul -i /etc/pki/koji/sigul-bridge.p12 -W ''

# NB: This process will not exit on SIGINT due to unfortunate behavior in NSPR.
# See https://bugzilla.redhat.com/show_bug.cgi?id=707382
exec /usr/sbin/sigul_bridge -v
