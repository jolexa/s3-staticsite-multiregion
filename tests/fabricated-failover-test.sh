#!/usr/bin/env bash
url="https://static-site.jolexa.us/region.html"

while true ; do
    region=$(curl -s $url)
    if [[ ${region} == "us-west-2" ]]; then
        echo "Site is at: ${region}, probably broken: $(date)"
        sleep 10
    else
        echo "Site is now in ${region}, working again: $(date)"
        break
    fi
done

