#!/bin/sh -e

# CA variables, replace as desired
# If these values are changed, they must be changed in koji-hub/Dockerfie as well, when creating the ProxyDNs setting in /etc/koji-hub/hub.conf.
CA_COUNTRY="US"
CA_STATEORPROVINCE="Massachusetts"
CA_LOCALITY="Boston"
CA_ORGANIZATION="Koji in a Box"

create_certificate()
{
    basename="$1"
    secret_name="${basename}-certificate-key"

    # Remove the secret if it already exists
    if podman secret inspect "$secret_name" >/dev/null 2>&1 ; then
        podman secret rm "$secret_name"
    fi

    openssl req -new -noenc \
        -subj "/C=${CA_COUNTRY}/ST=${CA_STATEORPROVINCE}/L=${CA_LOCALITY}/O=${CA_ORGANIZATION}/OU=${basename}/CN=${basename}" \
        -newkey rsa:2048 -passout 'pass:' \
        -out "${basename}.csr" -keyout - | podman secret create "$secret_name" -
    openssl x509 -req -CA koji_ca_cert.crt -CAkey koji_ca_cert.key -passin 'pass:' \
        -in "${basename}.csr" -out "${basename}/${basename}.crt"
    rm "${basename}.csr"
}

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

# Copy the public certificate to each build context directory that needs it
cp koji_ca_cert.crt ./koji-hub/
cp koji_ca_cert.crt ./koji-admin/

# Create the certificate and private key for koji-hub
# Save the public certificate as koji-hub.crt
# Save the private key as a podman secret named koji-hub-certificate-key
if [ ! -f koji-hub/koji-hub.crt ]; then
    create_certificate koji-hub
fi

# Create the certificate for the admin user
if [ ! -f koji-admin/koji-admin.crt ]; then
    create_certificate koji-admin
fi
