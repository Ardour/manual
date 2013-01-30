#!/bin/sh

url=manual.ardour.org
user=ardourstatic

echo "Uploading site to $url"
echo

rsync -av --progress --delete _site/ ${user}@${url}:${url}/

echo
echo "You can go visit $url now :)"
