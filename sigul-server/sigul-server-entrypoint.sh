#!/bin/sh -e

# REQUIRED ENVIRONMENT VARIABLES
# - SIGUL_SERVER_CERTIFICATE_KEY: path to the certificate key
# - SIGUL_SERVER_PACKAGE_SIGNING_KEY: path to the private key for package signing
# - SIGUL_KEY_PASSPHRASE: path to a file containing the passphrase to use for the signing key in the sigul database
if [ -z "$SIGUL_SERVER_CERTIFICATE_KEY" ]; then
    echo "\$SIGUL_SERVER_CERTIFICATE_KEY must be set"
    exit 1
fi
if [ ! -f "$SIGUL_SERVER_CERTIFICATE_KEY" ]; then
    echo "$SIGUL_SERVER_CERTIFICATE_KEY not present"
    exit 1
fi

if [ -z "$SIGUL_SERVER_PACKAGE_SIGNING_KEY" ]; then
    echo "\$SIGUL_SERVER_PACKAGE_SIGNING_KEY must be set"
    exit 1
fi
if [ ! -f "$SIGUL_SERVER_PACKAGE_SIGNING_KEY" ]; then
    echo "$SIGUL_SERVER_PACKAGE_SIGNING_KEY not present"
    exit 1
fi

if [ -z "$SIGUL_KEY_PASSPHRASE" ]; then
    echo "\$SIGUL_KEY_PASSPHRASE must be set"
    exit 1
fi
if [ ! -f "$SIGUL_KEY_PASSPHRASE" ]; then
    echo "$SIGUL_KEY_PASSPHRASE not present"
    exit 1
fi

# Remove everything under /var/lib/sigul in case this is a restart, reinitialize from scratch
rm -rf /var/lib/sigul/*
mkdir /var/lib/sigul/gnupg
chmod 0700 /var/lib/sigul/gnupg

# Initialize the certificate database
mkdir -p /var/lib/sigul/nss
certutil -d /var/lib/sigul/nss -N --empty-password

# Add the CA certificate
certutil -d /var/lib/sigul/nss -A -n koji_ca_cert -t CT,, -a -i /etc/pki/koji/koji_ca_cert.crt

# Add the client certificate
cat /etc/pki/koji/sigul-server.crt "$SIGUL_SERVER_CERTIFICATE_KEY" > /etc/pki/koji/sigul-server.pem
openssl pkcs12 -export -in /etc/pki/koji/sigul-server.pem -out /etc/pki/koji/sigul-server.p12 -name sigul-server-cert -passout 'pass:'
pk12util -d /var/lib/sigul/nss -i /etc/pki/koji/sigul-server.p12 -W ''

sigul_server_create_db
printf '\0' | sigul_server_add_admin -n sigul-client --batch

# Add the signing key
/server_add_key.py --key-file "$SIGUL_SERVER_PACKAGE_SIGNING_KEY" --key-admin sigul-client --key-name package-signing --new-key-passphrase-file "$SIGUL_KEY_PASSPHRASE"

exec /usr/sbin/sigul_server -v
