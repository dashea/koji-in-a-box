ARG dockerarch
# hadolint ignore=DL3029
FROM --platform=$dockerarch docker.io/library/fedora:36

RUN dnf install --repo=fedora -y koji-builder-0:1.28.0-1.fc36 \
                                 koji-0:1.28.0-1.fc36 && \
    dnf clean all

# /etc/kojid/kojid.conf: set URLs and certificate paths, enable createrepo_c
#  (koji-builder.pem is created in the entrypoint)
# /etc/koji.conf.d/localhost: Create a koji profile pointing to the koji-hub container
#  (koji-builder-probe.pem is created in the entrypoint)
RUN sed -i -e 's|^server=.*|server=https://koji-hub/kojihub|' \
           -e 's|^topurl=.*|topurl=https://koji-hub/kojifiles|' \
           -e 's|^;cert =.*|cert = /etc/pki/koji/koji-builder.pem|' \
           -e 's|^;serverca =.*|serverca = /etc/pki/koji/koji_ca_cert.crt|' \
           -e 's|^allowed_scms=.*|allowed_scms=git:/*:no|' \
           -e 's|^; use_createrepo_c=.*|use_createrepo_c = True|' \
           -e 's|^; topdir=.*|topdir = /mnt/koji|' \
           /etc/kojid/kojid.conf && \
    { \
        echo "[local-koji]"; \
        echo "server = https://koji-hub/kojihub"; \
        echo "authtype = ssl"; \
        echo "cert = /etc/pki/koji/koji-builder-probe.pem"; \
        echo "serverca = /etc/pki/koji/koji_ca_cert.crt"; \
    } >> /etc/koji.conf.d/localhost.conf

# Add the public certificates and CA certificate
ARG arch
ENV ARCH=$arch
COPY ./koji-builder-$arch.crt /etc/pki/koji/koji-builder.crt
COPY ./koji-builder-probe.crt /etc/pki/koji/koji-builder-probe.crt
COPY ./koji_ca_cert.crt /etc/pki/koji/koji_ca_cert.crt

COPY ./koji-builder-entrypoint.sh /
ENTRYPOINT ["/koji-builder-entrypoint.sh"]
