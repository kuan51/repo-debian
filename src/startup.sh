#!/bin/sh
apache2ctl -D FOREGROUND && \
echo "Debian Repository Server Started"
tail -f /var/log/apache2/*.log