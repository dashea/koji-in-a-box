# hadolint ignore=DL3029
FROM --platform=$BUILDPLATFORM docker.io/library/fedora:36

RUN dnf install --repo=fedora -y git-daemon-0:2.35.1-1.fc36 && \
    dnf clean all

VOLUME /var/lib/git
ENTRYPOINT ["git", "daemon", "--base-path=/var/lib/git", "--export-all"]
