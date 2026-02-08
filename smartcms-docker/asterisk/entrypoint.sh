#!/bin/bash

# Fix permissions
chown -R asterisk:asterisk /etc/asterisk /var/lib/asterisk /var/log/asterisk /var/spool/asterisk /var/run/asterisk 2>/dev/null

# Configure Asterisk from env
[ -n "$AMI_SECRET" ] && sed -i "s/secret = .*/secret = ${AMI_SECRET}/" /etc/asterisk/manager.conf 2>/dev/null
[ -n "$ARI_PASSWORD" ] && sed -i "s/password = .*/password = ${ARI_PASSWORD}/" /etc/asterisk/ari.conf 2>/dev/null
if [ -n "$EXTERNAL_IP" ]; then
    sed -i "s/external_media_address=.*/external_media_address=${EXTERNAL_IP}/" /etc/asterisk/pjsip.conf 2>/dev/null
    sed -i "s/external_signaling_address=.*/external_signaling_address=${EXTERNAL_IP}/" /etc/asterisk/pjsip.conf 2>/dev/null
fi

exec asterisk -fvvvg -c
