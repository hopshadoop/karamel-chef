#!/bin/bash
set -e
if [ ! -d "dela" ]; then
  echo "Run the script from the karamel-chef dir"
  exit 1
fi
./dela/demodela_1.sh demodela
./run.sh ubuntu 1 demodela