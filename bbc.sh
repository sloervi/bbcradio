#!/bin/sh
# bbc.sh
# A Wrapper around bbc.pl
# get rBBC Radio Shows
# sloervi McMurphy 28.08.2016

# TERM Variable is used

TERM=vt100
export TERM

# WHere to put all the radio shows
OUTDIR=/data
SENKE=$OUTDIR/log

# Plugins for get_iplayer
cd /root
PLUGINS=/config/plugins.tgz
test -f $PLUGINS && /bin/tar xzf $PLUGINS

# Create Directories if neccessary
test -d $OUTDIR || mkdir $OUTDIR
test -d $SENKE || mkdir $SENKE

# Logfile
LOGFILE=${SENKE}/bbclog.txt

# Get a list of all available radio shows
LIST=${SENKE}/radiolist.txt
echo "TYPE RADIO" > $LOGFILE
# --force, da er sonst fragt, ob alte Files gelÃ¶scht werden sollen
/usr/local/bin/get_iplayer/get_iplayer --force --type radio > $LIST

# put search items in this config file
for SENDUNG in `cat /config/bbc.txt`
do
        echo "/usr/local/bin/bbc/bbc.pl --senke $SENKE --sendung $SENDUNG $LIST" >> $LOGFILE
        /usr/local/bin/bbc/bbc.pl --nocleanup --senke $SENKE --sendung $SENDUNG $LIST
done

# Cleanup
cd $OUTDIR

find * -type f -name \*.wma -exec rm {} \;
find * -type f -name \*.flv -exec rm {} \;

date >> $LOGFILE
echo "bbc.sh READY" >> $LOGFILE
