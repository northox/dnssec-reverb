#!/bin/sh
# dnssec-reverb: DNSSEC key management tool
#
# @home: https://github.com/northox/dnssec-reverb
# @license: Simplified BSD
# Copyright (c) 2018 Juuso "Linda" Lapinlampi <linda@lindalap.fi>. 
# Copyright (c) 2017 Danny Fullerton <danny@mantor.org>. 
# Copyright (c) 2009-2013 Kazunori Fujiwara <fujiwara@wide.ad.jp>.

PROG=$(basename "$0")
DIR=$(dirname "$0")
keygen="$(which ldns-keygen)"
signzone="$(which ldns-signzone)"
key2ds="$(which ldns-key2ds)"
checkzone="$(which nsd-checkzone)"
control="$(which nsd-control)"
RELOAD_COMMAND="$checkzone \$ZONE \$ZONE || exit 1; $control reload && $control notify"
KSK_PARAM="-a ECDSAP256SHA256 -k"
ZSK_PARAM="-a ECDSAP256SHA256 "
SIGN_PARAM="-n"
DS_PARAM="-n -2"
SERIAL_TAG="_SERIAL_"

NOW=$(date +%Y%m%d%H%M%S)
LOCKF=""

Fatal()
{
	[ "$LOCKF" != "" ] && rm $LOCKF
	echo "$PROG: $1" >&2
	exit 1
}

# load conf
CONF="dnssec-reverb.conf"
if [ -r "$DNSSEC_REVERB_CONF/$CONF" ]; then
	CONF="$DNSSEC_REVERB_CONF/$CONF"
elif [ -r "$DIR/$CONF" ]; then
	CONF="${DIR}/$CONF"
elif [ -r "/etc/$CONF" ]; then
	CONF="/etc/$CONF"
elif [ -r "/usr/local/etc/$CONF" ]; then
	CONF="/usr/local/etc/$CONF"
else
	Fatal "Can't find config file"
fi
. "$CONF"

# defaults
[ "$keygen" = "" ] && Fatal "Can't find \$keygen"
[ "$signzone" = "" ] && Fatal "Can't find \$signzone"
[ "$key2ds" = "" ] && Fatal "Can't find \$key2ds"
[ "$checkzone" = "" ] && Fatal "Can't find \$checkzone"
[ "$control" = "" ] && Fatal "Can't find \$control"
[ "$MASTERDIR" = "" ] && Fatal "\$MASTERDIR not set"
[ -d "$MASTERDIR" ] || Fatal "\$MASTERDIR not a directory ($MASTERDIR)"
[ "$DBDIR" = "" ] && DBDIR="$MASTERDIR/dnssec-reverb-db"
[ "$KEYDIR" = "" ] && KEYDIR="$DBDIR/keydir"
[ "$KEYBACKUPDIR" = "" ] && KEYBACKUPDIR="$DBDIR/backup"
[ "$SERIALDIR" = "" ] && SERIALDIR="$DBDIR/serial"
[ "$DSDIR" = "" ] && DSDIR="$DBDIR/ds"
HEAD_ZSKNAME="zsk-"
HEAD_KSKNAME="ksk-"
HEAD_ZSSNAME="zss-"
HEAD_ZSRNAME="zsr-" # Removed ZSK
HEAD_KSSNAME="kss-"

# setup
[ ! -d "$DBDIR" ] && mkdir -p "$DBDIR"
[ ! -d "$KEYBACKUPDIR" ] && mkdir -p "$KEYBACKUPDIR"
[ ! -d "$KEYDIR" ] && mkdir -p "$KEYDIR"
[ ! -d "$SERIALDIR" ] && mkdir -p "$SERIALDIR"
[ ! -d "$DSDIR" ] && mkdir -p "$DSDIR"

cd "$MASTERDIR" || Fatal "Can't change directory to \$MASTERDIR"

_check_file()
{
	while [ "$1" != "" ]; do
		[ ! -s "$1" ] && Fatal "$1 does not exist."
		shift
	done
}

_check_nofile()
{
	while [ "$1" != "" ]; do
		[ -f "$1" ] && Fatal "$1 exist."
		shift
	done
}

_usage()
{
	[ "$LOCKF" != "" ] && rm $LOCKF
	cat <<EOF
usage: $PROG keygen <zone>
       $PROG rmkeys <zone>
       $PROG [-s] ksk-add <zone>
       $PROG [-s] ksk-roll <zone>
       $PROG [-s] zsk-add <zone>
       $PROG [-s] zsk-roll <zone>
       $PROG [-s] zsk-rmold <zone>
       $PROG sign <zone>
       $PROG status <zone>
EOF
	exit 1
}

sign()
{
	_check_file "$ZONEFILE" "$KSK_FILE" "$ZSK_FILE"
	KSK=$(head -1 "$KSK_FILE")
	ZSK=$(head -1 "$ZSK_FILE")
	KSS=""
	[ -s "$KSK_S_FILE" ] && KSS=$(head -1 "$KSK_S_FILE")
	_check_file "$KEYDIR/$KSK.private" "$KEYDIR/$ZSK.private"

	LASTSERIAL=0
	[ -f "$SERIAL_FILE" ] && LASTSERIAL=$(cat "$SERIAL_FILE")
	LASTDATE=$(echo "$LASTSERIAL" | sed 's/..$//')
	DATE=$(date +%Y%m%d)
	if [ "$LASTDATE" = "$DATE" ]; then
		SERIAL=$(( "$LASTSERIAL" + 1 ))
		echo "$SERIAL" > "$SERIAL_FILE"
 	else
		SERIAL=$(date +%Y%m%d00)
		echo "$SERIAL" > "$SERIAL_FILE"
	fi

	ZONE_PREPROCESS="sed s/$SERIAL_TAG/$SERIAL/"
	$ZONE_PREPROCESS "$ZONEFILE" > "$ZONEFILE.tmp"

	cat "$KSK_FILE" "$ZSK_FILE" | while read -r keyfile
	do
		_check_file "$KEYDIR/$keyfile.key"
		cat "$KEYDIR/$keyfile.key" >> "$ZONEFILE.tmp"
	done
	for i in $KSK_S_FILE $ZSK_S_FILE $ZSK_R_FILE
	do
		if [ -s "$i" ]; then
			keyfile=$(head -1 "$i")
			_check_file "$KEYDIR/$keyfile.key"
			cat "$KEYDIR/$keyfile.key" >> "$ZONEFILE.tmp"
		fi
	done
	[ "$KSS" != "" ] && KSS="$KEYDIR/$KSS"
	$signzone "$_SIGN_PARAM" -o "$ZONE" -f "$ZONEFILE.signed" "$ZONEFILE.tmp" "$KEYDIR/$ZSK" "$KEYDIR/$KSK" "$KSS"
	echo "signzone returns $?"
	rm "$ZONEFILE.tmp"
	eval "$RELOAD_COMMAND"
}

status()
{
	DS_FILE_TMP="$DS_FILE.tmp"
	if [ -f "$KSK_FILE" ]; then
		printf "%s's KSK = " "$ZONE"
		cat "$KSK_FILE";
		$key2ds "$_DS_PARAM" "$KEYDIR/$(cat "$KSK_FILE").key" | tee "$DS_FILE_TMP"
	fi
	if [ -f "$KSK_S_FILE" ]; then
		printf "%s's next KSK = " "$ZONE"
		cat "$KSK_S_FILE";
		$key2ds "$_DS_PARAM" "$KEYDIR/$(cat "$KSK_S_FILE").key" | tee -a "$DS_FILE_TMP"
	fi
	if [ -f "$ZSK_FILE" ]; then
		printf "%s's ZSK = " "$ZONE"
		cat "$ZSK_FILE";
	fi
	if [ -f "$ZSK_S_FILE" ]; then
		printf "%s's next ZSK = " "$ZONE"
		cat "$ZSK_S_FILE";
	fi
	if [ -f "$ZSK_R_FILE" ]; then
		printf "%s's previous ZSK = " "$ZONE"
		cat "$ZSK_R_FILE";
	fi
	mv -f "$DS_FILE_TMP" "$DS_FILE"
}

keygensub()
{
	cd "$KEYDIR" || Fatal "Can't change directory to \$KEYDIR"
	echo "$keygen $1 $2"
	newfile="$3"
	tmpfile="$3.tmp"
	_KEY=$($keygen "$1" "$2")
	[ -f "$_KEY.ds" ] && rm "$_KEY.ds"
	if [ ! -s "$_KEY.key" ]; then
		rm "$_KEY.key"
		Fatal "cannot write new key: $1 $2 $3"
	fi
	echo "$_KEY" > "$tmpfile"
	read -r "_KEY2" < "$tmpfile"
	if [ "$_KEY" != "$_KEY2" ]; then
		rm "$tmpfile"
		rm "$_KEY.key"
		Fatal "cannot write $tmpfile"
	fi
	mv "$tmpfile" "$newfile"
	cd "$MASTERDIR" || Fatal "Can't change directory to \$MASTERDIR"
}

removekeys_sub()
{
	if [ -f "$1" ]; then
		KEY=$(head -1 "$1")
		if [ -f "$KEYDIR/$KEY.key" ]; then
			mv "$KEYDIR/$KEY.key" "$KEYDIR/$KEY.private" "$KEYBACKUPDIR/"
		fi
	fi
}

remove_previouskey()
{
	if [ -f "$ZSK_R_FILE" ]; then
		removekeys_sub "$ZSK_R_FILE"
		mv "$ZSK_R_FILE" "$KEYBACKUPDIR/removed-ZSK-$NOW-$ZONE"
	fi
}

if [ "$1" = "" ] || [ "$1" = "-h" ] || [ "$1" = "-?" ] || [ "$1" = "--help" ]; then
	_usage
	exit 0
elif [ "$1" = "-s" ] || [ "$1" = "--sign" ];then
	SIGN_OPT=1
	shift
fi

CMD="$1"
shift

if [ "$1" = "" ]; then
	Fatal "A zone must be provided."
else
	ZONELIST="$*"
fi

for ZONE in $ZONELIST
do
	LOCKF="$DBDIR/$ZONE.lock"
	TMPF="$DBDIR/$ZONE.$$"
	KSK_FILE="$KEYDIR/$HEAD_KSKNAME$ZONE"
	ZSK_FILE="$KEYDIR/$HEAD_ZSKNAME$ZONE"
	KSK_S_FILE="$KEYDIR/$HEAD_KSSNAME$ZONE"
	ZSK_S_FILE="$KEYDIR/$HEAD_ZSSNAME$ZONE"
	ZSK_R_FILE="$KEYDIR/$HEAD_ZSRNAME$ZONE"
	SERIAL_FILE="$SERIALDIR/$ZONE"
	DS_FILE="$DSDIR/$ZONE"
	ZONEFILE="$MASTERDIR/$ZONE"
	ZONE_=$(echo "$ZONE" | tr .- __)
	eval _SIGN_PARAM=\${SIGN_PARAM_"$ZONE_":-"$SIGN_PARAM"}
	eval _KSK_PARAM=\${KSK_PARAM_"$ZONE_":-"$KSK_PARAM"}
	eval _ZSK_PARAM=\${ZSK_PARAM_"$ZONE_":-"$ZSK_PARAM"}
	eval _DS_PARAM=\${DS_PARAM_"$ZONE_":-"$DS_PARAM"}

	echo "LOCK$$" > "$TMPF"
	LOCKSTR=$(cat "$TMPF")
	if [ ! -f "$TMPF" ] || [ "LOCK$$" != "$LOCKSTR" ]; then
		Fatal "cannot write lock file $TMPF"
	fi
	if ln "$TMPF" "$LOCKF"; then
		:
	else
		rm "$TMPF"
		echo "zone $ZONE locked"
		continue
	fi
	rm "$TMPF"
	case $CMD in
	keygen)
		_check_nofile "$KSK_FILE" "$ZSK_FILE"
		keygensub "$_KSK_PARAM" "$ZONE" "$KSK_FILE"
		keygensub "$_ZSK_PARAM" "$ZONE" "$ZSK_FILE"
		status
		;;
	rmkeys)
		removekeys_sub "$KSK_FILE"
		removekeys_sub "$ZSK_FILE"
		removekeys_sub "$KSK_S_FILE"
		removekeys_sub "$ZSK_S_FILE"
		rm "$KSK_FILE" "$ZSK_FILE" "$KSK_S_FILE" "$ZSK_S_FILE"
		status
		;;
	ksk-add)
		_check_nofile "$KSK_S_FILE"
		keygensub "$_KSK_PARAM" "$ZONE" "$KSK_S_FILE"
		status
		;;
	ksk-roll)
		_check_file "$ZONEFILE" "$KSK_FILE" "$KSK_S_FILE"
		KSK=$(head -1 "$KSK_FILE")
		KSS=$(head -1 "$KSK_S_FILE")
		_check_file "$KEYDIR/$KSK.key" "$KEYDIR/$KSS.key" "$KEYDIR/$KSK.private" "$KEYDIR/$KSS.private"
		mv "$KEYDIR/$KSK.key" "$KEYDIR/$KSK.private" "$KEYBACKUPDIR/"
		mv "$KSK_S_FILE" "$KSK_FILE"
		OLDKSK="$KSK"
		KSK="$KSS"
		KSS=""
		echo "$ZONE 's KSK: valid -> removed: $OLDKSK"
		echo "$ZONE 's KSK: next  -> current: $KSK"
		status
		;;
	zsk-add)
		_check_nofile "$ZSK_S_FILE"
		keygensub "$_ZSK_PARAM" "$ZONE" "$ZSK_S_FILE"
		status
		;;
	zsk-roll)
		_check_file "$ZONEFILE" "$ZSK_FILE" "$ZSK_S_FILE"
		ZSK=$(head -1 "$ZSK_FILE")
		ZSS=$(head -1 "$ZSK_S_FILE")
		_check_file "$KEYDIR/$ZSK.key" "$KEYDIR/$ZSS.key" "$KEYDIR/$ZSK.private" "$KEYDIR/$ZSS.private"
		remove_previouskey
		mv "$ZSK_FILE" "$ZSK_R_FILE"
		mv "$ZSK_S_FILE" "$ZSK_FILE"
		OLDZSK="$ZSK"
		ZSK="$ZSS"
		ZSS=""
		echo "$ZONE 's ZSK: valid -> previous: $OLDZSK"
		echo "$ZONE 's ZSK: next -> current: $ZSK"
		status
		;;
	zsk-rmold)
		_check_file "$ZSK_R_FILE"
		remove_previouskey
		status
		;;
	sign)
		sign
		;;
	status)
		status
		;;
	*)
		echo "unknown command: $CMD"
		_usage
		;;
	esac
	rm "$LOCKF"
done

[ "$SIGN_OPT" = 1 ] && sign
exit 0
