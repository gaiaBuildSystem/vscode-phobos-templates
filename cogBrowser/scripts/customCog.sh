#!/bin/bash

_ARCH="arm64"

# download the packages depending on the machine arch
if [ "$MACHINE" == "intel" ] || [ "$MACHINE" == "qemux86-64" ]; then
    _ARCH="amd64"
fi

# make sure that there was not old ones there
rm -rf ./*.deb

wget -q \
    https://github.com/gaiaBuildSystem/webkit/releases/download/v2.38.6-1/wpewebkit-driver_2.38.6-1_${_ARCH}.deb
wget -q \
    https://github.com/gaiaBuildSystem/webkit/releases/download/v2.38.6-1/libwpewebkit-1.1-dev_2.38.6-1_${_ARCH}.deb
wget -q \
    https://github.com/gaiaBuildSystem/webkit/releases/download/v2.38.6-1/libwpewebkit-1.1-0_2.38.6-1_${_ARCH}.deb
wget -q \
    https://github.com/gaiaBuildSystem/cog/releases/download/debian-0.16.1-1-gaia-2/cog_0.16.1-1_${_ARCH}.deb

sudo apt install ./*.deb -y --allow-downgrades

# cleanup
rm -rf ./*.deb
