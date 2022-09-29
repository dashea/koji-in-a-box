#!/bin/sh -e

# REQUIRED ENVIRONMENT VARIABLES
# - MESSAGE_BUS_CERTIFICATE_KEY: path the private key for the TLS certificate
if [ -z "$MESSAGE_BUS_CERTIFICATE_KEY" ]; then
    echo "\$MESSAGE_BUS_CERTIFICATE_KEY must be set"
    exit 1
fi
if [ ! -f "$MESSAGE_BUS_CERTIFICATE_KEY" ]; then
    echo "$MESSAGE_BUS_CERTIFICATE_KEY not present"
    exit 1
fi

cp "$MESSAGE_BUS_CERTIFICATE_KEY" /etc/pki/rabbitmq/message-bus.key

cd /var/lib/rabbitmq
exec /usr/lib/rabbitmq/bin/rabbitmq-server
