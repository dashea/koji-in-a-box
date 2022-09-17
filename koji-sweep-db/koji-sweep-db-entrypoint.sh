#!/bin/sh -e

# REQUIRED ENVIRONMENT VARIABLE
# - POSTGRES_PASSWORD_FILE: path to a file containing the password for the koji user in postgres

if [ -z "$POSTGRES_PASSWORD_FILE" ]; then
    echo "\$POSTGRES_PASSWORD_FILE must be set"
    exit 1
fi
if [ ! -f "$POSTGRES_PASSWORD_FILE" ]; then
    echo "$POSTGRES_PASSWORD_FILE not present"
    exit 1
fi

# Create a configuration file containing the database password
touch /etc/koji-hub/hub.conf.d/secret.conf
chown root:apache /etc/koji-hub/hub.conf.d/secret.conf
chmod 0640 /etc/koji-hub/hub.conf.d/secret.conf
cat - >> /etc/koji-hub/hub.conf.d/secret.conf << EOF
[hub]
DBConnectionString = dbname=koji user=koji host=db port=5432 password=$(cat "$POSTGRES_PASSWORD_FILE")
EOF

exec /usr/sbin/crond -i -n
