#!/bin/sh -e

# CA variables, replace as desired
# If these values are changed, they must be changed in koji-hub/proxy-dns.conf and dist-git/ssl.conf as well
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

create_localhost_certificate()
{
    basename="$1"
    secret_name="${basename}-certificate-key"

    # Remove the secret if it already exists
    if podman secret inspect "$secret_name" >/dev/null 2>&1 ; then
        podman secret rm "$secret_name"
    fi

    cat - > "${basename}.cfg" << EOF
[req]
req_extensions = req_ext

[req_ext]
subjectAltName = @alt_names

[alt_names]
DNS.1 = $basename
DNS.2 = localhost
DNS.3 = localhost.localdomain
EOF

    openssl req -new -noenc \
        -subj "/C=${CA_COUNTRY}/ST=${CA_STATEORPROVINCE}/L=${CA_LOCALITY}/O=${CA_ORGANIZATION}/OU=${basename}/CN=${basename}" \
        -config "${basename}.cfg" \
        -newkey rsa:2048 -passout 'pass:' \
        -out "${basename}.csr" -keyout - | podman secret create "$secret_name" -
    openssl x509 -req -CA koji_ca_cert.crt -CAkey koji_ca_cert.key -passin 'pass:' \
        -copy_extensions copy \
        -in "$basename".csr -out "${basename}/${basename}.crt"
    rm "${basename}.cfg" "${basename}.csr"
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
cp koji_ca_cert.crt ./koji-web/
cp koji_ca_cert.crt ./koji-builder/
cp koji_ca_cert.crt ./kojira/
cp koji_ca_cert.crt ./dist-git/
cp koji_ca_cert.crt ./sigul-bridge/
cp koji_ca_cert.crt ./sigul-server/

# Create the certificate and private key for koji-hub
# Save the public certificate as koji-hub.crt
# Save the private key as a podman secret named koji-hub-certificate-key
if [ ! -f koji-hub/koji-hub.crt ]; then
    create_localhost_certificate koji-hub
fi

# Create the certificate for the admin user
# Save this one on the filesystem instead of storing as a podman secret
if [ ! -f ./koji-admin.pem ]; then
    openssl req -new -noenc \
        -subj "/C=${CA_COUNTRY}/ST=${CA_STATEORPROVINCE}/L=${CA_LOCALITY}/O=${CA_ORGANIZATION}/OU=koji-admin/CN=koji-admin" \
        -newkey rsa:2048 -passout 'pass:' \
        -out koji-admin.csr -keyout koji-admin.key
    openssl x509 -req -CA koji_ca_cert.crt -CAkey koji_ca_cert.key -passin 'pass:' \
        -in koji-admin.csr -out koji-admin.crt
    cat koji-admin.crt koji-admin.key > koji-admin.pem

    rm koji-admin.csr koji-admin.crt koji-admin.key
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
    create_localhost_certificate koji-web
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

# Create the kojira user certificate
if [ ! -f kojira/kojira.crt ]; then
    create_certificate kojira
fi

# Create the dist-git certificate
if [ ! -f dist-git/dist-git.crt ]; then
    create_localhost_certificate dist-git
fi

# Create the certificate for sigul-bridge
if [ ! -f sigul-bridge/sigul-bridge.crt ]; then
    create_certificate sigul-bridge
fi

# Create the certificate for sigul-server
if [ ! -f sigul-server/sigul-server.crt ]; then
    create_certificate sigul-server
fi

# Create a key pair for package signing
if [ ! -f ./package-signing-pub.key ]; then
    mkdir gpg-tmp
    chmod 0700 gpg-tmp
    gpg --homedir "$PWD/gpg-tmp" --batch --passphrase='' --quick-generate-key fedora-addons@reallylongword.org
    gpg --homedir "$PWD/gpg-tmp" --export -o ./package-signing-pub.key -a fedora-addons@reallylongword.org

    if podman secret inspect sigul-server-package-signing-key >/dev/null 2>&1 ; then
        podman secret rm sigul-server-package-signing-key
    fi

    gpg --homedir "$PWD/gpg-tmp" --export-secret-key -o - fedora-addons@reallylongword.org | podman secret create sigul-server-package-signing-key -

    rm -r gpg-tmp
fi

# Generate a passphrase for the signing key
podman secret inspect sigul-key-passphrase >/dev/null 2>&1 || \
    openssl rand -base64 32 | podman secret create sigul-key-passphrase -

echo ""
echo "Install certificate files on the host system:"
echo ""
echo "cp koji_ca_cert.crt ~/.koji/local-koji-serverca.crt"
echo "cp koji-user.pem ~/.koji/local-koji-user.pem"
echo "cp koji-admin.pem ~/.koji/local-koji-admin.pem"
echo ""
echo "Add koji_ca_cert.crt to your web browser as a certificate authority"
echo "Add koji-user.p12 to your web browser as a user certificate"
