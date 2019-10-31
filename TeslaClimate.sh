#!/bin/sh

DIR=$(dirname $0)
TIME=$1

if [ -z "$TIME" ]
then 
  echo "usage: $0 <YYYYmmddHHMM>"
  exit 1
fi

NOW=$(date +%Y%m%d%H%M)
if [ $TIME -le $NOW ]
then 
  echo "error: time is in the past"
  exit 1
fi
if [ $TIME -ge 204001010000 ]
then 
  echo "error: time is too future"
  exit 1
fi

at -q T -t $TIME <<_EOF_
cd $DIR
/usr/bin/tclsh TeslaClimate.tcl
_EOF_
exit 0
