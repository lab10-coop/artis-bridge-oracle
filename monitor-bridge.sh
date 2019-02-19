# that's a bit hacky, but works as long as (only) our service names start with "bridge-"
journalctl -f -u bridge-*
