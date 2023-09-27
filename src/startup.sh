#!/bin/sh
apache2ctl -D FOREGROUND && \
tail -f /var/log/apache2/*.log