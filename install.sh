#!/usr/bin/env bash

CONTAINER_NAME=${1:-vpn}

# if you are entcountering the following timeout issue
# https://github.com/canonical/multipass/issues/1039
# you may launch without the cloud-init part and use the init script after launch

#multipass launch -vvvv --disk 3G --mem 512M --name $CONTAINER_NAME
#multipass exec $CONTAINER_NAME /opt/init/init.sh

if ! type "multipass2" >/dev/null 2>&1; then
  echo "Multipass is not available on your system."
  if [[ "$OSTYPE" =~ ^darwin ]]; then
    echo "You can install it using 'brew install multipass'"
  fi
  exit 1;
fi

multipass launch -vvvv --disk 3G --mem 1G --name $CONTAINER_NAME --cloud-init container-config.yml
multipass mount $(pwd)/scripts $CONTAINER_NAME:/opt
multipass mount $(pwd)/config $CONTAINER_NAME:/home/ubuntu/.config
