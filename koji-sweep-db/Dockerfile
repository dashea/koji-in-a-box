# hadolint ignore=DL3029
FROM --platform=$BUILDPLATFORM docker.io/library/fedora:36

RUN dnf install --repo=fedora -y koji-hub-0:1.28.0-1.fc36 \
                                 cronie-0:1.5.7-4.fc36 \
                                 cronie-anacron-0:1.5.7-4.fc36 && \
    dnf clean all

COPY ./anacrontab /etc/anacrontab
COPY ./koji-sweep-db-entrypoint.sh /
ENTRYPOINT ["/koji-sweep-db-entrypoint.sh"]
