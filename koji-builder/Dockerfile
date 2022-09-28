ARG dockerarch
# hadolint ignore=DL3029
FROM --platform=$dockerarch docker.io/library/fedora:36

RUN dnf install --repo=fedora -y koji-builder-0:1.28.0-1.fc36 \
                                 patch-0:2.7.6-16.fc36 && \
    dnf clean all

COPY ./kojid.conf /etc/kojid/kojid.conf

# Add the public certificates and CA certificate
ARG arch
COPY ./koji-builder-$arch.crt /etc/pki/koji/koji-builder.crt

# Add the CA certificate as a system CA to simplify running mock
# Mock will need the CA in order to download dependencies via koji-hub
COPY ./koji_ca_cert.crt /etc/pki/ca-trust/source/anchors/
RUN update-ca-trust extract

# qemu bombs out in mock in the forked config read process for somewhat baffling but pinpointable reasons.
# monkey patch the offending function call away
COPY ./0001-Skip-the-setregid-call-in-_elevatePrivs.patch /mock.patch
RUN patch /usr/lib/python3.10/site-packages/mockbuild/uid.py /mock.patch

COPY ./koji-builder-entrypoint.sh /
VOLUME /mnt/koji
ENTRYPOINT ["/koji-builder-entrypoint.sh"]
