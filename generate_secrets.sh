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
    directory="${2:-$1}"
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
        -in "${basename}.csr" -out "${directory}/${basename}.crt"
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
cp koji_ca_cert.crt ./koji-web/
cp koji_ca_cert.crt ./koji-builder/

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

# Create a non-admin user certificate
# Do this one manually since the key will be saved on the filesystem instead of stored as a podman secret
if [ ! -f ./koji-user.pem ]; then
    openssl req -new -noenc \
        -subj "/C=${CA_COUNTRY}/ST=${CA_STATEORPROVINCE}/L=${CA_LOCALITY}/O=${CA_ORGANIZATION}/OU=koji-user/CN=koji-user" \
        -newkey rsa:2048 -passout 'pass:' \
        -out koji-user.csr -keyout koji-user.key
    openssl x509 -req -CA koji_ca_cert.crt -CAkey koji_ca_cert.key -passin 'pass:' \
        -in koji-user.csr -out koji-user.crt
    cat koji-user.crt koji-user.key > koji-user.pem

    # Create a pkcs12 certificate for use with a web browser
    openssl pkcs12 -export -inkey koji-user.key -in koji-user.crt -passout 'pass:' \
        -CAfile koji_ca_cert.crt -out koji-user.p12

    rm koji-user.csr koji-user.crt koji-user.key
fi

# Create the koji-web certificate
if [ ! -f koji-web/koji-web.crt ]; then
    cat - > koji-web.cfg << EOF
[req]
req_extensions = req_ext

[req_ext]
subjectAltName = @alt_names

[alt_names]
DNS.1 = koji-web
DNS.2 = localhost
DNS.3 = localhost.localdomain
EOF

    if podman secret inspect "koji-web-certificate-key" >/dev/null 2>&1 ; then
        podman secret rm "koji-web-certificate-key"
    fi

    openssl req -new -noenc \
        -subj "/C=${CA_COUNTRY}/ST=${CA_STATEORPROVINCE}/L=${CA_LOCALITY}/O=${CA_ORGANIZATION}/OU=koji-web/CN=koji-web" \
        -config koji-web.cfg \
        -newkey rsa:2048 -passout 'pass:' \
        -out koji-web.csr -keyout - | podman secret create "koji-web-certificate-key" -
    openssl x509 -req -CA koji_ca_cert.crt -CAkey koji_ca_cert.key -passin 'pass:' \
        -copy_extensions copy \
        -in koji-web.csr -out koji-web/koji-web.crt
    rm koji-web.cfg koji-web.csr
fi

# Create a secret for the `Secret` setting of koji-web
podman secret inspect koji-web-secret >/dev/null 2>&1 || \
    openssl rand -base64 32 | podman secret create koji-web-secret -

# Create the koji-builder certificates
if [ ! -f koji-builder/koji-builder-aarch64.crt ]; then
    create_certificate koji-builder-aarch64 koji-builder
fi

if [ ! -f koji-builder/koji-builder-x86_64.crt ]; then
    create_certificate koji-builder-x86_64 koji-builder
fi

# Create a non-admin user certificate for use by the builders' readiness probe.
if [ ! -f koji-builder/koji-builder-probe.crt ]; then
    create_certificate koji-builder-probe koji-builder
fi

echo ""
echo "Install certificate files on the host system:"
echo ""
echo "cp koji_ca_cert.crt ~/.koji/local-koji-serverca.crt"
echo "cp koji-user.pem ~/.koji/local-koji-user.pem"
echo ""
echo "Add koji_ca_cert.crt to your web browser as a certificate authority"
echo "Add kojiadmin.p12 to your web browser as a user certificate"
