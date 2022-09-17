FROM docker.io/library/fedora:36

RUN dnf install --repo=fedora -y koji-hub-0:1.28.0-1.fc36 \
                                 cronie-0:1.5.7-4.fc36 \
                                 cronie-anacron-0:1.5.7-4.fc36 && \
    dnf clean all

# Create the anacrontab to run koji-sweep-db once a day
# Delete all the garbage that anacrontab comes with
# MAILTO="" disables the attempt to email job output anywhere.
# The awful looking redirects send the job output to the stdout and stderr of the entrypoint
# process, so it gets displayed on the host in the normal way.
RUN { \
        echo 'MAILTO=""'; \
        echo "@daily 0 koji-sweep-db /usr/sbin/koji-sweep-db >/proc/1/fd/1 2>/proc/1/fd/2"; \
    } > /etc/anacrontab

COPY ./koji-sweep-db-entrypoint.sh /
ENTRYPOINT ["/koji-sweep-db-entrypoint.sh"]
