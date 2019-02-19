services_file=systemd-units.list
if [[ ! -f $services_file ]]; then
        echo "ERR: File $services_file doesn't exist. Did you set up the bridge? Are you in the bridge-oracle directory?"
        exit 1
fi

systemctl status `cat $services_file`
