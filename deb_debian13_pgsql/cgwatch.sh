#!/bin/bash
watch "systemd-cgls -k --no-pager -c -u oar.slice && echo ======== && systemctl list-units --legend=0 --all oar*"
