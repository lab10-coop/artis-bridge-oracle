#!/bin/bash

set -e
set -u

if [[ $UID != 0 ]]; then
        echo "must be run as root"
        exit 1
fi

services_file=systemd-units.list
if [[ ! -f $services_file ]]; then
	echo "ERR: File $services_file doesn't exist. Did you set up the bridge? Are you in the bridge-oracle directory?"
	exit 1
fi

for s in `cat $services_file`; do 
	echo "stopping $s..."
	systemctl stop $s

        if [[ ${1-} == "--persist" ]]; then
                echo "disabling $s (no autoboot)"
                systemctl disable $s
        fi
done

echo "all done"
