#!/bin/sh
set -eu
cd /srv/bikenavi
test -f .bikenavi-owned
install -m 644 ops/bikenavi-osm-update.service /etc/systemd/system/bikenavi-osm-update.service
install -m 644 ops/bikenavi-osm-update.timer /etc/systemd/system/bikenavi-osm-update.timer
systemctl daemon-reload
systemctl enable --now bikenavi-osm-update.timer
systemctl start --no-block bikenavi-osm-update.service
