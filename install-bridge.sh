#!/bin/bash

set -e
set -u

# Setup for bridge-oracle, to be run as root. Tested on Ubuntu 18.04 only.
# Installs dependencies, the application and creates systemd units.
# Based on this docs: https://github.com/poanetwork/token-bridge#installation-and-deployment

### SCRIPT CONFIG ###

service_rootdir=/etc/systemd/system
if [[ $# != 1 ]]; then
	echo "usage: $0 <user>"
	echo "Assumptions:"
	echo " - a group with the same name as <user> exists"
	echo " - the application is located in the current working directory"
	exit 1
fi

if ! awk -F':' '{ print $1}' /etc/passwd | grep -q $1; then
	echo "ERR: /etc/passwd doesn't list a user named $1"
	exit 1
fi
service_user=$1
service_group=$service_user

# sloppy check if we're in the right dir
if ! cat package.json | grep -q bridge; then
	echo "ERR: There's no package.json mentioning 'bridge'. Please cd to the directory with the bridge-oracle application."
	exit 1
fi
service_workdir=`pwd`

if [[ $UID != 0 ]]; then
	echo "must be run as root"
	exit 1
fi

### DEPENDENCIES ###

if ! dpkg -s build-essential > /dev/null; then
	echo "installing build-essential"
	apt install -y build-essential
	# maybe not all of those are needed, but at least make and g++ are
fi

if [[ ! -f nodesource_setup.sh ]]; then
	echo "installing nodejs and npm"
	# the npm package provided by the OS itself is too old
	curl -sL https://deb.nodesource.com/setup_8.x -o nodesource_setup.sh && bash nodesource_setup.sh
	apt update
	apt install -y nodejs
fi

#echo "installing node and npm..."
#apt install -y nodejs npm

if ! systemctl is-active --quiet redis-server; then
	echo "installing redis-server..."
	apt install -y redis-server rabbitmq-server
fi

if ! systemctl is-active --quiet rabbitmq-server; then
	echo "installing rabbitmq-server..."
	apt install rabbitmq-server

	# bind rabbitmq to localhost only for security reasons
	# working config found [here](https://github.com/LibreTime/libretime/issues/316#issuecomment-334965321)
	cat <<EOF > /etc/rabbitmq/rabbitmq-env.conf
NODE_IP_ADDRESS=127.0.0.1

export RABBITMQ_NODENAME=rabbit@localhost
export RABBITMQ_NODE_IP_ADDRESS=127.0.0.1
export ERL_EPMD_ADDRESS=127.0.0.1
export RABBITMQ_CONFIG_FILE="/etc/rabbitmq/rabbit"
EOF

	cat <<EOF > /etc/rabbitmq/rabbit.config
[
    {rabbitmq_management, [
        {listener, [{port, 25672}, {ip, "127.0.0.1"}]}
    ]},
    {kernel, [
        {inet_dist_use_interface,{127,0,0,1}}
    ]}
].
EOF
	echo "restarting rabbitmq bound to localhost..."
	systemctl restart rabbitmq-server.service
fi

### APPLICATION ###

if [[ ! -f .env ]]; then
        echo "config file '.env' missing"
	exit 1
fi

echo "running npm ci..."
su $service_user -c "npm ci"

### SERVICES SETUP ###

services_file=systemd-units.list
if [[ -f $services_file ]]; then
	echo "file $services_file already exists, skipping service setup. Delete the file if you want to overwrite existing unit files"
else
	echo "setting up systemd unit files for user $service_user, working directory $service_workdir in directory $service_rootdir..."

	service_cmds=( "watcher:signature-request" "watcher:collected-signatures" "watcher:affirmation-request" "sender:home" "sender:foreign" )

	for service_cmd in "${service_cmds[@]}"; do 
		service_name="bridge-${service_cmd/:/-}"
		echo "setting up systemd service unit $service_name"

	cat <<EOF > $service_rootdir/$service_name.service
[Unit]
Description=ARTIS $service_name
[Service]
User=$service_user
Group=$service_group
WorkingDirectory=$service_workdir
Environment=NODE_ENV=production
# see https://code.lab10.io/graz/04-artis/bridges/bridge-oracle#configuration-parameters
Environment=LOG_LEVEL=info
ExecStart=/usr/bin/npm run $service_cmd
Restart=always

[Install]
WantedBy=multi-user.target
EOF
		echo "$service_name" >> $services_file
	done

	systemctl daemon-reload
fi
