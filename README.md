# Multi-arch koji environment for docker-compose

This project defines a multi-architecture koji build system that can be run on a single machine as a set of non-root containers.
This is a pretty weird thing to want to do.

## How to use

### Host setup

Install the necessary packages on your host system:

```sh
sudo dnf install koji podman podman-compose openssl qemu-user-static rpkg
```

Create a koji profile pointing to your local servers.
The `generate_secrets.sh` script will create credentials for both regular and admin users, which can be accessed as separate koji profiles.

```sh
mkdir ~/.koji
cat - > ~/.koji/config <<EOF
[local-koji]
server = https://localhost:8081/kojihub
topurl = http://localhost:8083/kojifiles
weburl = https://localhost:8080/koji
authtype = ssl
cert = ~/.koji/local-koji-user.pem
serverca = ~/.koji/local-koji-serverca.crt

[local-admin]
server = https://localhost:8081/kojihub
weburl = https://localhost:8080/koji
authtype = ssl
cert = ~/.koji/local-koji-admin.pem
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

### SELinux modifications

mock performs several remounts of ephemeral filesystems, which selinux as currently configured in Fedora forbids.
Create a custom policy to allow mock to run inside a container.

Create the following file as `mock-mount.te`:

```sepolicy
module mock-mount 1.0;

require {
	type tmpfs_t;
	type proc_t;
	type devpts_t;
	type sysfs_t;
	type device_t;
	type container_t;
	class filesystem { mount remount };
	class dir mounton;
}

#============= container_t ==============
allow container_t device_t:filesystem remount;
allow container_t devpts_t:filesystem mount;
allow container_t proc_t:dir mounton;
allow container_t sysfs_t:filesystem remount;
allow container_t tmpfs_t:filesystem mount;
```

Compile and install the module:

```sh
checkmodule -M -m -o mock-mount.mod mock-mount.te
semodule_package -o mock-mount.pp -m mock-mount.mod
sudo semodule -i mock-mount.pp
```

Additionally, git-daemon is not configured for container usage, so make some modifications there.

Create the following as git-daemon-container.pp:

```sepolicy
module git-daemon-container 1.0;

require {
	type git_sys_content_t;
	type container_t;
	class file { map open read };
	class dir read;
}

#============= container_t ==============
allow container_t git_sys_content_t:dir read;
allow container_t git_sys_content_t:file { open read };
allow container_t git_sys_content_t:file map;
```

and:

```sh
checkmodule -M -m -o git-daemon-container.mod git-daemon-container.te
semodule_package -o git-daemon-container.pp -m git-daemon-container.mod
sudo semodule -i git-daemon-container.pp
```

Of course, this all has security implications so be aware of what you're doing and don't just blindly trust me, a person who does not understand nor care to understand selinux.

### Initialize the secrets

Run `./generate_secrets.sh` to create the necessary certificate files and add secrets to podman.

Copy the koji-user certificates to your home directory:

```sh
cp koji_ca_cert.crt ~/.koji/local-koji-serverca.crt
cp koji-user.pem ~/.koji/local-koji-user.pem
cp koji-admin.pem ~/.koji/local-koji-admin.pem
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
The path can be any readable path, but if you're using selinux the easiest way to get things to cooperate permissions-wise is to create a directory beneath `/var/lib/git`.
The path is passed to podman-compose via the `KOJI_GIT_PATH` environment variable.

```sh
sudo mkdir /var/lib/git/local-koji
sudo chown $UID:$GID /var/lib/git/local-koji
export KOJI_GIT_PATH=/var/lib/git/local-koji
```

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

The first thing to do is create some tags.
Create a tag to act as a root of the repository you will be creating, a build tag beneath the repository tag, and a destination tag that builds will be tagged into.

```sh
koji -p local-admin add-tag --arches="x86_64 aarch64" f36-addons
koji -p local-admin add-tag --parent f36-addons --arches "x86_64 aarch64" f36-addons-build
koji -p local-admin add-tag --parent f36-addons --arches="x86_64 aarch64" f36-addons-signing-pending
```

If starting with external repos, see [External Repository Server Bootstrap](https://docs.pagure.org/koji/external_repo_server_bootstrap/).
Otherwise see [Koji Server Bootstrap](https://docs.pagure.org/koji/server_bootstrap/).

The following example adds Fedora 36 as an external repo:

```sh
koji -p local-admin add-external-repo -t f36-addons-build f36-repo https://dl.fedoraproject.org/pub/fedora/linux/releases/36/Everything/\$arch/os/
koji -p local-admin add-external-repo -t f36-addons-build f36-updates-repo https://dl.fedoraproject.org/pub/fedora/linux/updates/36/Everything/\$arch/
```

Add the -build tag as a build target, and tag builds into the -signing-pending tag:

```sh
koji -p local-admin add-target f36-addons f36-addons-build f36-addons-signing-pending
```

Add build groups to the build tag:

```sh
koji -p local-admin add-group f36-addons-build build
koji -p local-admin add-group f36-addons-build srpm-build
```

Add packages to the build groups.
If basing things on Fedora, it's probably easiest to just do what Fedora did.
See [Koji Server Bootstrap](https://docs.pagure.org/koji/server_bootstrap/) for information on fetching the Fedora configuration.
Running commands against the Fedora koji instance require that you be a Fedora packager and authenticated via krb5.

The following adds the packages currently configured for Fedora 36 in the `build` and `srpm-build` groups:

```sh
koji -p local-admin add-group-pkg f36-addons-build build bash bzip2 coreutils cpios diffutils fedora-release findutils gawk glibc-minimal-langpack grep gzip info patch redhat-rpm-config rpm-build sed shadow-utils tar unzip util-linux which xz
koji -p local-admin add-group-pkg f36-addons-build srpm-build bash fedora-release fedpkg-minimal glibc-minimal gnupg2 redhat-rpm-config rpm-build shadow-utils
```

Generate the repo:

```sh
koji -p local-admin regen-repo f36-addons-build
```

This will probably take a while.
At the end of the process, you should have a koji environment ready to accept builds.

### Setup the common repo

The builders are configured to download package sources using a script in the 'common' repo.
The script does not exist yet.
The build chroot used by `buildSRPMFromSCM` will include the `fedpkg-minimal` package, which can be configured to download sources from the local dist-git server.
Just set the `baseurl` environment variable and call `fedpkg-base`.

```sh
git init --bare "${KOJI_GIT_PATH}/rpms/common.git"
tmpdir="$(mktemp -d)"
( cd "$tmpdir"
  git clone "${KOJI_GIT_PATH}/rpms/common.git" common
  cd common
  echo '#!/bin/sh' > get_sources
  echo 'baseurl=https://dist-git/repo/pkgs/rpms fedpkg-base' >> get_sources
  chmod +x get_sources
  git add get_sources
  git commit -m 'Add the get_sources script'
  git push
)
rm -rf "$tmpdir"
```

## Building a package

Ok so it's running now what

### CLI setup

#### Rant

The usual way to interact with dist-git repos is `rpkg`, the library that `fedpkg` is built on.
Fedora has two versions of `rpkg`, and both of them are broken.

The `rpkg` command from the `rpkg-utils` source package is abandoned and buggy and oriented specifically around [COPR](https://copr.fedorainfracloud.org/) usage.
Attempting to upload a source file will crash because it calls its own git status function with the wrong number of arguments.

`fedpkg` is currently built on top of the `pyrpkg` library in the `rpkg` source package.
`pyrpkg` doesn't support certificate settings when downloading files, and also doesn't actually read certificate settings from the config.
Additionally, it's not usable without some additional work.
`pyrpkg` has Red Hat specific settings hard coded in multiple places, and `fedpkg` solves this by overriding the code itself instead of setting options via the config file.
Additionally, while the upstream (pyrpkg) [rpkg](https://pagure.io/rpkg) project includes a CLI frontend, Fedora packages it in `/usr/share/rpkg/examples` instead of `/usr/bin`, so that it doesn't conflict with the `rpkg` command from `rpkg-utils` (the broken one, above).

The `pyrpkg` option ultimately offers the least amount of friction.
It's what's used for "normal" Fedora build environments, and the source download using `fedpkg-minimal` will use the same assumptions used in a `pyrpkg`-based source upload.
Some commands are still unusuable with the script below (like `srpm` and `build`), but it's not the end of the world.

I dunno, everything sucks.

#### Configuration

Create a CLI frontend from the example.
The following script is based on /usr/share/rpkg/examples/cli/usr/bin/rpkg.
The default config path has been changed to ~/.config/rpkg/mypkg.conf, and it patches the `pyrpkg.Commands` class to work around the missing certificate settings.
The script also sets `source_entry_type`, which is also not read from the config file for some reason.
Install the script as `mypkg` somewhere in your path; e.g., `~/.local/bin/mypkg`.

```python
#!/usr/bin/env python
# rpkg - a script to interact with the Red Hat Packaging system
#
# Copyright (C) 2011 Red Hat Inc.
# Author(s): Jesse Keating <jkeating@redhat.com>
#
# This program is free software; you can redistribute it and/or modify it
# under the terms of the GNU General Public License as published by the
# Free Software Foundation; either version 2 of the License, or (at your
# option) any later version.  See http://www.gnu.org/copyleft/gpl.html for
# the full text of the license.

import argparse
import logging
import os
import sys

import six
from six.moves import configparser

import pyrpkg
import pyrpkg.cli
import pyrpkg.utils

# Setup an argparser and parse the known commands to get the config file
parser = argparse.ArgumentParser(add_help=False)
parser.add_argument('-C', '--config', help='Specify a config file to use',
                    default=os.path.join(os.path.expanduser('~'), '.config', 'rpkg', 'mypkg.conf'))

(args, other) = parser.parse_known_args()

# Make sure we have a sane config file
if not os.path.exists(args.config) and not other[-1] in ['--help', '-h']:
    sys.stderr.write('Invalid config file %s\n' % args.config)
    sys.exit(1)

# Setup a configuration object and read config file data
if six.PY2:
    config = configparser.SafeConfigParser()
else:
    # The SafeConfigParser class has been renamed to ConfigParser in Python 3.2.
    config = configparser.ConfigParser()
config.read(args.config)

client = pyrpkg.cli.cliClient(config)
client.do_imports()
client.parse_cmdline()

if not client.args.path:
    try:
        client.args.path = pyrpkg.utils.getcwd()
    except:
        print('Could not get current path, have you deleted it?')
        sys.exit(1)

# Set source_entry_type to the format used by fedpkg
cmd = client.cmd
cmd.source_entry_type = 'bsd'

# Patch in the missing SSL settings
# ca_cert and cert_file are unsettable properties, so replace them in the class
config = dict(client.config.items(client.name, raw=True))
pyrpkg.Commands.ca_cert = config['ca_cert']
pyrpkg.Commands.cert_file = config['client_cert']

# setup the logger -- This logger will take things of INFO or DEBUG and
# log it to stdout.  Anything above that (WARN, ERROR, CRITICAL) will go
# to stderr.  Normal operation will show anything INFO and above.
# Quiet hides INFO, while Verbose exposes DEBUG.  In all cases WARN or
# higher are exposed (via stderr).
log = pyrpkg.log
client.setupLogging(log)

if client.args.v:
    log.setLevel(logging.DEBUG)
elif client.args.q:
    log.setLevel(logging.WARNING)
else:
    log.setLevel(logging.INFO)

# Run the necessary command
try:
    sys.exit(client.args.command())
except KeyboardInterrupt:
    pass
```

Make the script executable.

```sh
chmod +x ~/.local/bin/mypkg
```

Create a configuration file with the local dist-git settings.

```sh
mkdir -p ~/.config/rpkg
cat - > ~/.config/rpkg/mypkg.conf <<EOF
[mypkg]
lookaside = https://localhost:8082/repo/pkgs
lookasidehash = sha512
lookaside_cgi = https://localhost:8082/repo/pkgs/upload.cgi
gitbaseurl = file://${KOJI_GIT_PATH}/rpms/%(repo)s.git
anongiturl = file://${KOJI_GIT_PATH}/rpms/%(repo)s.git
branchre = f\d$|f\d\d$|el\d$|main$
kojiprofile = local-koji
build_client = koji
ca_cert = ${HOME}/.koji/local-koji-serverca.crt
client_cert = ${HOME}/.koji/local-koji-user.pem
EOF
```

### Add a new package

The following example uses the [mkrpm](https://github.com/dashea/mkrpm) project.
I don't remember if `mkrpm` actually works or not, but it is some C code that compiles and is not packaged in Fedora, so it's good enough for here.

Add the package to your destination koji tag.

```sh
koji -p local-admin add-pkg --owner koji-user f36-addons
```

Create the git repository.
Add an empty .gitignore to initialize it.

```sh
git init --bare "${KOJI_GIT_PATH}/rpms/mkrpm.git"
tmpdir="$(mktemp -d)"
( cd "$tmpdir"
  git clone "${KOJI_GIT_PATH}/rpms/mkrpm.git" mkrpm
  cd mkrpm
  touch .gitignore
  git add .gitignore
  git commit -q -m 'Initial setup of the repo'
  git push
)
rm -rf "$tmpdir"
```

Check out a copy of the git repo.

```sh
mypkg clone mkrpm
cd mkrpm
```

Add a spec file as mkrpm.spec.

```specfile
%global commit 4f7587c3aa133bc834959065d3626f1bac5114ea
%global shortcommit 4f7587c

Name:    mkrpm
Version: 0^20190530git%{shortcommit}
Release: 1%{?dist}
Summary: Tool for creating RPM archives without a spec file

BuildRequires: autoconf
BuildRequires: automake
BuildRequires: libtool
BuildRequires: gcc
BuildRequires: libarchive-devel
BuildRequires: openssl-devel

# Used by tests
BuildRequires: libcmocka-devel
#BuildRequires: valgrind

# NB: Upstream references GPLv3 or newer in source header files, but does not include a copy of the GPL
# Upstream has been notified of this error but upstream also does not care very much
License: GPLv3+
URL:     https://github.com/dashea/mkrpm/
Source0: https://github.com/dashea/mkrpm/archive/%{commit}/%{name}-%{shortcommit}.tar.gz

%description
This is a tool to create a RPM of a file or directory, without the use of spec files,
rpmbuild, or librpm.

This utility was built mainly as a side-effect of an effort to decipher and document the RPM file format.
The actual utility may or may not work very well.

This is a pre-release version.

%prep
%autosetup -n mkrpm-%{commit}

%build
./autogen.sh
%configure
%make_build

%install
%make_install

%check
# The tests don't run in rpmbuild due to the dumb way I built things and I don't feel like fixing it
# make check check-valgrind

%files
%doc README.md docs/TAG-CODEX.txt
%{_bindir}/mkrpm

%changelog
* Sat Sep 24 2022 David Shea <reallylongword@gmail.com> - 0^20190530git457587c-1
- Initial package
```

Download the sources and add them to dist-git.

```sh
spectool --get-files mkrpm.spec
mypkg new-sources mkrpm-4f7587c.tar.gz
```

Commit and push.
The `sources` and `.gitignore` file should already be staged for commit by `rpkg`.

```sh
git add mkrpm.spec
git commit -m 'Initial package'
git push
```

Build it.
This command would be less ugly if one of the rpkg-based tools was set up right so uh FIXME I guess.
The `main` fragment is the name of the git branch.
Replace this with the value you use as `init.defaultBranch` (e.g., `master`).

```sh
koji -p local-koji build f36-addons 'git://git/rpms/mkrpm.git?#main'
```

### Create a repo

The simplest way to create a dnf repository from your built packages is the `koji dist-repo` command.

`dist-repo` takes a tag name and a GPG key ID.
The key ID is the last eight digits of the GPG key ID, lowercased.

For example, if gpg output the following:

```sh
$ gpg --show-key package-signing-pub.key
pub   ed25519 2022-10-19 [SC] [expires: 2024-10-18]
      47D719538AEE21C236B1DB588E25E94194AF4640
uid                      fedora-addons@reallylongword.org
sub   cv25519 2022-10-19 [E]
```

The key ID would be `94af4640`.

Or, using the shell to parse the output:

```sh
KEYID="$(gpg --show-key --with-colons package-signing-pub.key | grep '^fpr:' | head -n 1 | sed 's/.*\([A-Z0-9]\{8\}\):$/\1/' | tr '[:upper:]' '[:lower:]')"
```

and then:

```sh
koji -p local-koji dist-repo --with-src --split-debuginfo --write-signed-rpms f36-addons $KEYID
```

The repo can now be found under http://localhost:8083/kojifiles/repos-dist/.

For more advanced compose options, see the [pungi](https://docs.pagure.org/pungi/index.html) tool.

## Other notes

### Authentication

Koji provides two choices for authentication: kerberos or SSL certificates.
This project uses SSL certificates.

A major downside of using SSL certificates for authentication is that the root of authentication is a file stored on the host system.
As defined in [generate_secrets.sh](generate_secrets.sh), the CA certificate and private key are stored on the filesystem with no password.
Anyone with access to the root certificate files will be able to take control of the build system.

The upside of using SSL certificates is that it's not kerberos.
