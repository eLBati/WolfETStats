#!/bin/sh
#
# ET Server log rotation by month
# (c) Tony J. White  [http://et.tjw.org]
#
# this is sample file, you have to fix file locations!
#
export ETS_PB_FILE=/usr/local/enemy-territory/home/et/.etwolf/sv_cheat.log
THISMONTH=`date +%Y%m`
STATDIR="/home/chaos/tjw/HTML/et.tjw.org/ets/stats"
THEMEDIR="/home/chaos/tjw/HTML/et.tjw.org/ets/ets/themes/ets-light"
LOGFILE="/usr/local/enemy-territory/home/et/.etwolf/etmain/game.log"
if [ ! -d $STATDIR/$THISMONTH ]; then
	mkdir $STATDIR/$THISMONTH && \
	cp -a $THEMEDIR $STATDIR/$THISMONTH/ && \
	grep "  0:00 TIME:" "$LOGFILE" | tail -1 > "${LOGFILE}.tmp" && \
	mv "${LOGFILE}.tmp" "$LOGFILE" && \
	chown tjw:et "$LOGFILE" && \
	chmod g+w "$LOGFILE"
fi
cd /home/chaos/tjw/HTML/et.tjw.org/ets && \
	./ets/ets.pl \
	$LOGFILE \
	stats/$THISMONTH/ ets-light
