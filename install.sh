#!/usr/bin/env bash

set -eu

cd "$(dirname "$0")"

CONTAINER_NAME=${1:-vpn}

if ! type "multipass" >/dev/null 2>&1; then
  echo "Multipass is not available on your system."
  if [[ "$OSTYPE" =~ ^darwin ]]; then
    echo "You can install it using 'brew install multipass'"
  fi
  exit 1;
fi

multipass launch --name $CONTAINER_NAME --cloud-init container-config.yml
multipass mount $(pwd)/scripts $CONTAINER_NAME:/opt
multipass mount $(pwd)/config $CONTAINER_NAME:/home/ubuntu/.config
multipass mount $(pwd)/log $CONTAINER_NAME:/home/ubuntu/log
multipass exec $CONTAINER_NAME switch-dns