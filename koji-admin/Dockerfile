# hadolint ignore=DL3029
FROM --platform=$BUILDPLATFORM docker.io/library/fedora:36

RUN dnf install --repo=fedora -y koji-0:1.28.0-1.fc36 && \
    dnf clean all

COPY ./koji.conf /etc/koji.conf

# Add the public certificate and CA certificate
COPY ./koji-admin.crt /etc/pki/koji/koji-admin.crt
COPY ./koji_ca_cert.crt /etc/pki/koji/koji_ca_cert.crt

COPY ./koji-admin-entrypoint.sh /
ENTRYPOINT ["/koji-admin-entrypoint.sh"]
