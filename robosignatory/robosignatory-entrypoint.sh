#!/bin/sh -e

# REQUIRED ENVIRONMENT VARIABLE
# - ROBOSIGNATORY_CERTIFICATE_KEY: path to a file containing the private key
# - SIGUL_KEY_PASSPHRASE: passphrase for the key in sigul
if [ -z "$ROBOSIGNATORY_CERTIFICATE_KEY" ]; then
    echo "\$ROBOSIGNATORY_CERTIFICATE_KEY must be set"
    exit 1
fi

if [ ! -f "$ROBOSIGNATORY_CERTIFICATE_KEY" ]; then
    echo "$ROBOSIGNATORY_CERTIFICATE_KEY not present"
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

# Create the key and pem files from the secrets
mkdir -p /etc/pki/koji
cp "$ROBOSIGNATORY_CERTIFICATE_KEY" /etc/pki/koji/robosignatory.key
cat /etc/pki/koji/robosignatory.crt /etc/pki/koji/robosignatory.key > /etc/pki/koji/robosignatory.pem

# Set up the passphrase
# Use the "test method for "binding" the passphrase, since there's not any hardware we can bind it to
printf '[{"method": "test", "value": "%s", "may_unbind": "1"}]' "$(cat "$SIGUL_KEY_PASSPHRASE")" > /etc/pki/koji/robosignatory.pass

# Initialize the certificate database for use with sigul
rm -rf /var/lib/sigul
mkdir -p /var/lib/sigul
certutil -d /var/lib/sigul -N --empty-password

# Add the CA certificate
certutil -d /var/lib/sigul -A -n koji_ca_cert -t CT,, -a -i /etc/pki/koji/koji_ca_cert.crt

# Add the client certificate
openssl pkcs12 -export -in /etc/pki/koji/robosignatory.pem -out /etc/pki/koji/robosignatory.p12 -name robosignatory-cert -passout 'pass:'
pk12util -d /var/lib/sigul -i /etc/pki/koji/robosignatory.p12 -W ''

# Set the key ID in robosignatory.toml
# The key ID is the last 8 of the ID output by gpg, lowercased
# Only the first fingerprint line counts, the second one is subkey information
keyid="$(gpg --import --import-options show-only --with-colons /etc/pki/koji/package-signing-pub.key | grep '^fpr:' | head -n 1 | sed 's/.*\([A-Z0-9]\{8\}\):$/\1/' | tr '[:upper:]' '[:lower:]')"
tomlq --toml-output ".consumer_config.koji_instances.primary.tags[0].keyid = \"${keyid}\"" < /etc/fedora-messaging/robosignatory.toml > /etc/fedora-messaging/tmp.toml
mv /etc/fedora-messaging/tmp.toml /etc/fedora-messaging/robosignatory.toml

exec /usr/bin/fedora-messaging --conf /etc/fedora-messaging/robosignatory.toml consume
