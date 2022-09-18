FROM docker.io/library/fedora:36

RUN dnf install --repo=fedora -y koji-0:1.28.0-1.fc36 && \
    dnf clean all

# Change the default profile to point to the koji-hub container
# koji-admin.pem will be created by the entrypoint
RUN sed -i -e 's|^server =.*|server = https://koji-hub/kojihub|' \
           -e 's|^authtype =.*|authtype = ssl|' \
           -e 's|^;cert =.*|cert = /etc/pki/koji/koji-admin.pem|' \
           -e 's|^;serverca =.*|serverca = /etc/pki/koji/koji_ca_cert.crt|' \
           /etc/koji.conf

# Add the public certificate and CA certificate
COPY ./koji-admin.crt /etc/pki/koji/koji-admin.crt
COPY ./koji_ca_cert.crt /etc/pki/koji/koji_ca_cert.crt

COPY ./koji-admin-entrypoint.sh /
ENTRYPOINT ["/koji-admin-entrypoint.sh"]
