#!/bin/sh
set -eu
cd /srv/bikenavi
test -f .bikenavi-owned
exec docker run --rm --name bikenavi-osm-update \
  --user "$(id -u):$(id -g)" --network host \
  --read-only --cap-drop ALL --security-opt no-new-privileges --cpus 1 \
  --mount type=bind,src=/srv/bikenavi/server/data/osm,dst=/maps \
  --mount type=bind,src=/srv/bikenavi/scripts,dst=/tools,readonly \
  --tmpfs /tmp bikenavi-backend python -u /tools/update_offline_extract.py /maps
