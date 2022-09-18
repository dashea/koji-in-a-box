# Multi-arch koji environment for docker-compose

This project defines a multi-architecture koji build system that can be run on a single machine as a set of non-root containers.
This is a pretty weird thing to want to do.

## How to use

### Host setup

Install the necessary packages on your host system:

```sh
dnf install koji podman podman-compose openssl
```

Create a koji profile pointing to your local servers:

```sh
mkdir ~/.koji
cat - <<EOF
[local-koji]
server = https://localhost:8080/kojihub
weburl = https://localhost:8080/koji
authtype = ssl
cert = ~/.koji/local-koji-user.pem
serverca = ~/.koji/local-koji-serverca.crt
EOF
```

### Initialize the secrets

Run `./generate_secrets.sh` to create the necessary certificate files and add secrets to podman.

Copy the koji-user certificates to your home directory:

```sh
cp koji_ca_cert.crt ~/.koji/local-koji-serverca.crt
cp koji-user.pem ~/.koji/local-koji-user.pem
```

Add the CA certificate to your web browser as a certificate authority.
In firefox, this is under Settings -> Certificates -> View Certificates... -> Authorities -> Import...
Import the `koji_ca_cert.crt` file.
Select the `Trust this CA to identify websites` option.
If you need to remove the CA, it will show up under the "Organization" value, "Koji in a Box".

Add the user certificate to your web browser.
In firefox, this is under Settings -> Certificates -> View Certificates... -> Your Certificates -> Import...
Import the `koji-user.p12` file.
The password is blank.

### Fire it up

Build the necessary container images:

```sh
podman-compose build
```

And then start everything up

```sh
podman-compose up
```

### Use it

The koji configuration above creates a profile named `local-koji`.
To access the koji services using the koji CLI, run `koji -p local-koji ...`.

## An overview of the guts

### Authentication

Koji provides two choices for authentication: kerberos or SSL certificates.
This project uses SSL certificates.

A major downside of using SSL certificates for authentication is that the root of authentication is a file stored on the host system.
As defined in [generate_secrets.sh](generate_secrets.sh), the CA certificate and private key are stored on the filesystem with no password.
Anyone with access to the root certificate files will be able to take control of the build system.

The upside of using SSL certificates is that it's not kerberos.
