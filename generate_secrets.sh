#!/bin/sh -e

# CA variables, replace as desired
CA_COUNTRY="US"
CA_STATEORPROVINCE="Massachusetts"
CA_LOCALITY="Boston"
CA_ORGANIZATION="Koji in a Box"

# Create a password for the koji-hub to postgres connection
# Do no replace the password if it is already set. The value is only used by the postgres
# container when the database is initially created. Replacing the postgres password after the database has been
# initialized will require replacing the secret AND changing the password in psql.
podman secret inspect koji-postgres-password >/dev/null 2>&1 || \
    openssl rand -base64 32 | podman secret create koji-postgres-password -

# Create the certificate authority that will act as the root for authenticating all services.
# Files are saved as koji_ca_cert.crt and koji_ca_cert.key
if [ ! -f koji_ca_cert.crt ]; then
    openssl req -new -x509 -extensions v3_ca \
        -subj "/C=${CA_COUNTRY}/ST=${CA_STATEORPROVINCE}/L=${CA_LOCALITY}/O=${CA_ORGANIZATION}/CN=koji-ca" \
        -days 3650 \
        -newkey rsa:2048 -passout 'pass:' -keyout koji_ca_cert.key \
        -out koji_ca_cert.crt
fi
