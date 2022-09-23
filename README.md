# Multi-arch koji environment for docker-compose

This project defines a multi-architecture koji build system that can be run on a single machine as a set of non-root containers.
This is a pretty weird thing to want to do.

## How to use

### Host setup

Install the necessary packages on your host system:

```sh
sudo dnf install koji podman podman-compose openssl qemu-user-static rpkg
```

Create a koji profile pointing to your local servers:

```sh
mkdir ~/.koji
cat - <<EOF
[local-koji]
server = https://localhost:8081/kojihub
weburl = https://localhost:8080/koji
authtype = ssl
cert = ~/.koji/local-koji-user.pem
serverca = ~/.koji/local-koji-serverca.crt
EOF
```

Running cross-arch builders is handled by qemu-user-static and binfmt_misc handlers registered by `systemd-binfmt`.
Some modifications to the binfmt settings are needed in order to allow mock to run, since it depends on an unreadable setuid binary.

```sh
for arch in x86_64 aarch64 ; do
  if [ -f /usr/lib/binfmt.d/qemu-$arch-static.conf ]; then
    sudo cp /usr/lib/binfmt.d/qemu-$arch-static.conf /etc/binfmt.d/
    sudo sed -i 's|:\([^:]*\)$|:OC\1|' /etc/binfmt.d/qemu-$arch-static.conf
  fi
done
sudo systemctl restart systemd-binfmt
```

This will add the `O` and `C` flags to the binfmt configuration.
`O` changes the behavior of binfmt_misc so that binfmt_misc will open the binary and pass a file descriptor to the interpreter (qemu) instead of passing a path to the interpeter and having the interpeter open the file.
This allows binfmt_misc to be used with non-readable files, in our case `/usr/sbin/userhelper`.
`C` instructs binfmt_misc to use the binary to calculate credentials of the new process, allowing for setuid/setgid binaries.

These flags have security implications for your host system and should be used with care.

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

## Building a package

Ok so it's running now what

### CLI setup

#### Rant

The usual way to interact with dist-git repos is `rpkg`, the library that `fedpkg` is built on.
Fedora has two versions of `rpkg`, and both of them are broken.

The `rpkg` command from the `rpkg-utils` source package is abandoned and buggy.
Attempting to upload a source file will crash because it calls its own git status function with the wrong number of arguments.

`fedpkg` is currently built on top of the `pyrpkg` library in the `rpkg` source package.
`pyrpkg` doesn't support certificate settings when downloading files, and also doesn't actually read certificate settings from the config.

`rpkg-utils` mostly works (the upload succeeds before the `git status` bombs out), and the upload issue can be fixed by https://pagure.io/rpkg-util/pull-request/47.
However, the commands and behavior are a little different from `fedpkg` since it's more oriented around COPR users, and since it's been abandoned it will likely stop working in the new future due to bit rot.
I dunno, everything sucks.

#### Configuration

Create a configuration file with the local dist-git settings.
By default, rpkg will check `~/.config/rpkg.conf` for the configuration file.

Here is an example configuration that uses the default /etc/rpkg.conf as a template.
The important parts are `clone_url`, `anon_clone_url`, `download_url`, `upload_url`, `cert_file` and `ca_cert`.
`cert_file` and `ca_cert` use the same paths as the example koji.conf above.
This example config also sets the base_output_path to the current directory because I found putting things in /tmp/rpkg to be kind of weird.

```sh
cat - > ~/.config/rpkg.conf <<EOF
[rpkg]
base_output_path = .

[git]
clone_url = file://${KOJI_GIT_PATH}/%(repo_path)s
anon_clone_url = file://${KOJI_GIT_PATH}/%(repo_path)s
default_namespace = rpms
push_follow_tags = True
clean_force = True
clean_dirs = True

[lookaside]
download_url = https://localhost:8082/repo/pkgs/%(repo_path)s/%(filename)s/%(hashtype)s/%(hash)s/%(filename)s
upload_url = https://localhosot:8082/repo/pkgs/upload.cgi
cert_file = ${HOME}/.koji/local-koji-user.pem
ca_cert = ${HOME}/.koji/local-koji-serverca.crt
EOF
```

### Add a new package

First, create the git repository.
Add an empty .gitignore to initialize it.

```sh
mkdir -p "${KOJI_GIT_PATH}"
git init --bare "${KOJI_GIT_PATH}/rpms/hello-world.git"
tmpdir="$(mktemp -d)"
( cd "$tmpdir"
  git clone "${KOJI_GIT_PATH}/rpms/hello-world.git hello-world"
  cd hello-world
  touch .gitignore
  git add .gitignore
  git commit -q -m 'Initial setup of the repo'
  git push
)
rm -rf "$tmpdir"
```

## Other notes

### Authentication

Koji provides two choices for authentication: kerberos or SSL certificates.
This project uses SSL certificates.

A major downside of using SSL certificates for authentication is that the root of authentication is a file stored on the host system.
As defined in [generate_secrets.sh](generate_secrets.sh), the CA certificate and private key are stored on the filesystem with no password.
Anyone with access to the root certificate files will be able to take control of the build system.

The upside of using SSL certificates is that it's not kerberos.
