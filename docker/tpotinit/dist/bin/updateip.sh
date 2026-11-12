#!/bin/bash
# Let's add the first local ip to the /tmp/etc/issue and both IPs to tpot_environment
# If the external IP cannot be detected, the internal IP will be inherited.
myUUID=$(cat /data/uuid)
myLOCALIP=$(ip address show | awk '/inet .*brd/{split($2,a,"/"); print a[1]; exit}')
myEXTIP=$(/opt/tpot/bin/myip.sh)
if [ "$myEXTIP" = "" ];
  then
    myEXTIP=$myLOCALIP
fi

myBLACKHOLE_STATUS=$(ip r | grep "blackhole" -c)
if [ "$myBLACKHOLE_STATUS" -gt "500" ];
  then
    myBLACKHOLE_STATUS="| [1;34mBLACKHOLE: [ [0;37mENABLED[1;34m ][0m"
  else
    myBLACKHOLE_STATUS="| [1;34mBLACKHOLE: [ [1;30mDISABLED[1;34m ][0m"
fi

# Build issue
echo "[H[2J" > /tmp/etc/issue
echo "T-Pot 23.12" >> /tmp/etc/issue
echo >> /tmp/etc/issue
echo ",---- [ [1;34m\n[0m ] [ [0;34m\d[0m ] [ [1;30m\t[0m ]" >> /tmp/etc/issue
echo "|" >> /tmp/etc/issue
echo "| [1;34mIP: $myLOCALIP ($myEXTIP)[0m" >> /tmp/etc/issue
echo "| [0;34mSSH: ssh -l tsec -p 64295 $myLOCALIP[0m" >> /tmp/etc/issue
#if [ "$myCHECKIFSENSOR" == "0" ];
#  then
echo "| [1;30mWEB: https://$myLOCALIP:64297[0m" >> /tmp/etc/issue
#fi
echo "| [0;37mADMIN: https://$myLOCALIP:64294[0m" >> /tmp/etc/issue
echo "$myBLACKHOLE_STATUS" >> /tmp/etc/issue
echo "|" >> /tmp/etc/issue
echo "\`----" >> /tmp/etc/issue
echo >> /tmp/etc/issue
tee /data/tpot/etc/compose/tpot_environment << EOF
HONEY_UUID=$myUUID
MY_EXTIP=$myEXTIP
MY_INTIP=$myLOCALIP
MY_HOSTNAME=$HOSTNAME
EOF
