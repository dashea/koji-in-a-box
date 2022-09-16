#!/bin/sh -e

# Create a password for the koji-hub to postgres connection
# Do no replace the password if it is already set. The value is only used by the postgres
# container when the database is initially created. Replacing the postgres password after the database has been
# initialized will require replacing the secret AND changing the password in psql.
podman secret inspect koji-postgres-password >/dev/null 2>&1 || \
    openssl rand -base64 32 | podman secret create koji-postgres-password -
