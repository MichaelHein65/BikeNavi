#!/bin/sh
# IPv6 egress for BikeNavi on the Pi's Docker 26 bridge. No inbound ports.
set -eu
PATH=/usr/sbin:/usr/bin:/sbin:/bin
export PATH
subnet='fd53:ba7e:91c4:1::/64'
bridge='bikenavi-v6'
if [ "${1:-}" = '--install' ]; then
    uplink=$(ip -6 route show default | awk '{for(i=1;i<=NF;i++) if($i=="dev") {print $(i+1); exit}}')
else
    uplink=${1:-}
fi
case "$uplink" in ''|*[!a-zA-Z0-9_-]*) echo 'A valid IPv6 uplink is required.' >&2; exit 1;; esac
[ -d "/proc/sys/net/ipv6/conf/$uplink" ]
if [ "${1:-}" = '--install' ]; then
    install -m 755 "$0" /usr/local/sbin/bikenavi-ipv6
    # Continue learning the router's prefix/default route when Docker enables forwarding.
    printf 'net.ipv6.conf.%s.accept_ra = 2\n' "$uplink" > /etc/sysctl.d/90-bikenavi-ipv6.conf
    cat > /etc/systemd/system/bikenavi-ipv6.service <<UNIT
[Unit]
Description=IPv6 internet access for the BikeNavi map downloader
Wants=network-online.target
After=network-online.target docker.service ufw.service
[Service]
Type=oneshot
ExecStart=/usr/local/sbin/bikenavi-ipv6 $uplink
RemainAfterExit=yes
[Install]
WantedBy=multi-user.target
UNIT
    systemctl daemon-reload
    systemctl enable bikenavi-ipv6.service
    systemctl restart bikenavi-ipv6.service
    exit
fi
sysctl -w "net.ipv6.conf.$uplink.accept_ra=2" net.ipv6.conf.all.forwarding=1
# Docker 26 on this Pi does not create IPv6 NAT/filter rules. Scope all rules
# to the dedicated bridge and ULA prefix; existing UFW/Tailscale policy remains.
ip6tables -w -t nat -C POSTROUTING -s "$subnet" -o "$uplink" -j MASQUERADE 2>/dev/null ||
    ip6tables -w -t nat -A POSTROUTING -s "$subnet" -o "$uplink" -j MASQUERADE
ip6tables -w -C FORWARD -i "$bridge" -o "$uplink" -s "$subnet" -j ACCEPT 2>/dev/null ||
    ip6tables -w -I FORWARD 1 -i "$bridge" -o "$uplink" -s "$subnet" -j ACCEPT
ip6tables -w -C FORWARD -i "$uplink" -o "$bridge" -d "$subnet" -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT 2>/dev/null ||
    ip6tables -w -I FORWARD 1 -i "$uplink" -o "$bridge" -d "$subnet" -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT
