# hadolint ignore=DL3029
FROM --platform=$BUILDPLATFORM docker.io/library/fedora:36
EXPOSE 443
EXPOSE 80

# Fedora docker images are built with tsflags=nodocs in dnf.conf.
# The koji-hub DDL is marked as a doc file, so disable this option when installing koji.
# koji-fedmsg-plugin is not packaged in Fedora, download it from copr
RUN dnf install --repo=fedora --setopt=tsflags= -y koji-0:1.28.0-1.fc36 && \
    dnf install --repo=fedora -y postgresql-0:14.1-3.fc36 \
                                 koji-hub-0:1.28.0-1.fc36 \
                                 dnf-plugins-core-4.1.0-1.fc36 \
                                 mod_ssl-1:2.4.53-1.fc36 && \
    dnf -y copr enable dshea/buildsys && \
    dnf -y install --repo=fedora,\*copr\* koji-fedmsg-plugin-0:0.1.0^20220713git52ace35-2.fc36 && \
    dnf clean all

# Create configuration files that do not depend on runtime secrets
COPY ./localhost-koji.conf /etc/koji.conf.d/localhost.conf
COPY ./hub.conf /etc/koji-hub/hub.conf
COPY ./ssl.conf /etc/httpd/conf.d/ssl.conf
COPY ./httpd-limits.conf /etc/httpd/conf.d/limits.conf
COPY ./kojihub-auth.conf /etc/httpd/conf.d/kojihub-auth.conf
COPY ./kojihub-servername.conf /etc/httpd/conf.d/kojihub-servername.conf
COPY ./fedmsg.toml /etc/fedora-messaging/config.toml

# Create the necessary filesystem skeleton under /mnt/koji
WORKDIR /mnt/koji
RUN mkdir packages repos work scratch repos-dist && \
    chown apache:apache packages repos work scratch repos-dist

# Add the public certificate and CA certificate
COPY ./koji-hub.crt /etc/pki/koji/koji-hub.crt
COPY ./koji_ca_cert.crt /etc/pki/koji/koji_ca_cert.crt

COPY ./koji-hub-entrypoint.sh /
VOLUME /mnt/koji
ENTRYPOINT ["/koji-hub-entrypoint.sh"]
