#! /bin/bash

hciconfig hci0 piscan || exit 1
hciconfig hci0 sspmode 1 || exit 2
