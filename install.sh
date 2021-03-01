#!/usr/bin/env bash

# https://github.com/canonical/multipass/issues/1039
#multipass launch -vvvv --disk 3G --mem 256M --name $1 --cloud-init cloud-init/container-config.yml &&
multipass launch -vvvv --disk 3G --mem 256M --name $1 &&
multipass mount $(pwd)/scripts $1:/opt &&
multipass mount $(pwd)/cloud-init $1:/etc/cloud-init