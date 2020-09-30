#!/bin/bash
cd ..
printf "Enter the Enterprise username: "
read  USERNAME
printf "Enter the Enterprise password: "
read -s PASSWORD
echo ""
export ENTERPRISE_USERNAME=$USERNAME

printf "Enter a name (prefix) for the VM: "
read name

echo "The cluster name prefix is: $name"

ENTERPRISE_PASSWORD=$PASSWORD ./hopsworks-cloud-installer.sh -n $name -i kubernetes -ni -c azure -d https://nexus.hops.works/repository -w 0 -g 0 --debug
