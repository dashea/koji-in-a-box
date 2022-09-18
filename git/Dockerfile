FROM docker.io/library/fedora:36

RUN dnf install --repo=fedora -y git-daemon-0:2.35.1-1.fc36 && \
    dnf clean all

ENTRYPOINT ["git", "daemon", "--base-path=/srv/git", "--export-all"]
