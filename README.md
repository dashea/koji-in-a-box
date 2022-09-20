# Multi-arch koji environment for docker-compose

This project defines a multi-architecture koji build system that can be run on a single machine as a set of non-root containers.
This is a pretty weird thing to want to do.

## How to use

### Host setup

Install the necessary packages on your host system:

```sh
sudo dnf install koji podman podman-compose openssl qemu-user-static
sudo systemctl restart systemd-binfmt
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

### Set up the git repositories

The git repositories are served out of a bind mount from the host's filesystem.
This way interacting with git on the host just be done through local files.

Create a directory where the git repos will live.
The path can be any readable path.

e.g., `mkdir ~/koji-git`.

The path is passed to podman-compose via the `KOJI_GIT_PATH` environment variable.
e.g., `export KOJI_GIT_PATH=~/koji-git`.

### Fire it up

Build the necessary container images:

```sh
podman-compose build
```

And then start everything up

```sh
podman-compose up
```

### Bootstrap the build environment

The koji-admin container provides the credentials for issuing admin commands to the koji-hub.
Enter the container to get started:

```sh
podman-compose exec koji-admin /bin/sh
```

The first thing to do is create some tags.
Create a tag to act as a root of the repository you will be creating, and a build tag beneath this tag.

```sh
koji add-tag f36-addons
koji add-tag --parent f36-addons --arches "x86_64 aarch64" f36-addons-build
```

If starting with external repos, see [External Repository Server Bootstrap](https://docs.pagure.org/koji/external_repo_server_bootstrap/).
Otherwise see [Koji Server Bootstrap](https://docs.pagure.org/koji/server_bootstrap/).

The following example adds Fedora 36 as an external repo:

```sh
koji add-external-repo -t f36-addons-build f36-repo https://dl.fedoraproject.org/pub/fedora/linux/releases/36/Everything/\$arch/os/
koji add-external-repo -t f36-addons-build f36-updates-repo https://dl.fedoraproject.org/pub/fedora/linux/updates/36/Everything/\$arch/
```

Add the -build tag as a build target:

```sh
koji add-target f36-addons f36-addons-build
```

Add build groups to the build tag:

```sh
koji add-group f36-addons-build build
koji add-group f36-addons-build srpm-build
```

Add packages to the build groups.
If basing things on Fedora, it's probably easiest to just do what Fedora did.
See [Koji Server Bootstrap](https://docs.pagure.org/koji/server_bootstrap/) for information on fetching the Fedora configuration, which you will not be able to do from within the containers because they lack the configuration and utilities and external internet access for krb5 authentication.
The following adds the packages currently configured for Fedora 36 in the `build` and `srpm-build` groups:

```sh
koji add-group-pkg f36-addons-build build bash bzip2 coreutils cpios diffutils fedora-release findutils gawk glibc-minimal-langpack grep gzip info patch redhat-rpm-config rpm-build sed shadow-utils tar unzip util-linux which xz
koji add-group-pkg f36-addons-build srpm-build bash fedora-release fedpkg-minimal glibc-minimal gnupg2 redhat-rpm-config rpm-build shadow-utils
```

Generate the repo:

```sh
koji regen-repo f36-addons-build
```

This will probably take a while.
At the end of the process, you should have a koji environment ready to accept builds.

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
