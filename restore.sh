#!/bin/bash

# Some global vars
myDATE=$(date +%Y%m%d%H%M%S)
myRED=$'\e[0;31m'
myGREEN=$'\e[0;32m'
myWHITE=$'\e[0;0m'
myBLUE=$'\e[0;34m'

myTPOTDIR="${HOME}/tpotce"
myBACKUPDIR="${HOME}/tpot_backups"
myARCHIVE=""
myCONFIRMED=""
# OpenSearch Dashboards runs with the basePath /dashboards and rewrites it, so its
# API only answers below that prefix
myDASHBOARDS="http://127.0.0.1:64296/dashboards"
myOS="http://127.0.0.1:64298"

# How long to wait for OpenSearch Dashboards before printing the commands to run by
# hand. Weaker hardware is allowed to take longer.
myDASHBOARDS_TIMEOUT="${TPOT_DASHBOARDS_TIMEOUT:-300}"
myTMPDIR=""

# What to restore. Empty means: ask.
myDO_GIT=""
myDO_CONFIG=""
myDO_PATCH=""
myDO_UNTRACKED=""
myDO_DATA=""
myDO_OPENSEARCH=""

myRESTORER=$(cat << "EOF"
 _____     ____       _     ____           _
|_   _|   |  _ \ ___ | |_  |  _ \ ___  ___| |_ ___  _ __ ___ _ __
  | |_____| |_) / _ \| __| | |_) / _ \/ __| __/ _ \| '__/ _ \ '__|
  | |_____|  __/ (_) | |_  |  _ <  __/\__ \ || (_) | | |  __/ |
  |_|     |_|   \___/ \__| |_| \_\___||___/\__\___/|_|  \___|_|
EOF
)

function fuPRINT_HELP () {
	cat <<EOF
Usage: $0 [-l] [-f <archive>] [-y]

Restores a backup written by update.sh.

Options:
  -l                List the available backups and what they hold
  -f <archive>      Restore from this archive. Default: the newest one in
                    ${myBACKUPDIR}
  -y                Restore everything without asking, including the rollback
                    of the git checkout
  -h                Show this help message

Without -y every group is offered separately, so you can bring back just the
configuration without touching anything else.
EOF
	exit 1
}

# Check if running with root privileges
if [ ${EUID} -eq 0 ];
  then
    echo "This script should not be run as root. Please run it as a regular user."
    echo
    exit 1
fi

# One working directory for the whole run, gone when the script ends
function fuTMPDIR () {
	[ -n "${myTMPDIR}" ] && return
	myTMPDIR=$(mktemp -d)
	if [ ! -d "${myTMPDIR}" ];
	  then
	    echo "###### $myBLUE""Could not create a temporary directory.""$myWHITE"" [ $myRED""NOT OK""$myWHITE ]"
	    echo
	    exit 1
	fi
	trap 'rm -rf "${myTMPDIR}"' EXIT
}

# All archives, newest first
function fuARCHIVE_LIST () {
	ls -1t "${myBACKUPDIR}"/*_tpot_backup*.tar 2>/dev/null
}

# What does the archive hold?
function fuHAS () {   # $1 = Member oder Praefix
	grep -q "$1" "${myTMPDIR}/toc" 2>/dev/null
}

# Does the archive hold OpenSearch state (Dashboards objects, ISM policy)?
function fuHAS_OPENSEARCH () {
	fuHAS "^opensearch/osd_export.ndjson$" || fuHAS "^opensearch/ism_policy_tpot.json$"
}

function fuLIST () {
	local myFILE=""
	local myKIND=""
	echo
	echo "### Backups in ${myBACKUPDIR} ..."
	if [ -z "$(fuARCHIVE_LIST)" ];
	  then
	    echo "###### $myBLUE""No backups found.""$myWHITE"
	    echo
	    exit 0
	fi
	for myFILE in $(fuARCHIVE_LIST);
	  do
	    case "${myFILE}" in
	      *_full*.tar) myKIND="full" ;;
	      *)           myKIND="regular" ;;
	    esac
	    echo
	    echo "###### $myBLUE$(basename "${myFILE}")$myWHITE  $(du -h "${myFILE}" | cut -f1), ${myKIND}"
	    tar xOf "${myFILE}" MANIFEST 2>/dev/null | sed -n '2,8p' | sed 's/^/         /'
	    echo "         Holds: $(tar tf "${myFILE}" 2>/dev/null | sed 's|/.*||' | sort -u | tr '\n' ' ')"
	done
	echo
	exit 0
}

# Pick the archive and read its table of contents
function fuPICK_ARCHIVE () {
	echo
	echo "### Looking for a backup ..."
	if [ -z "${myARCHIVE}" ];
	  then
	    myARCHIVE=$(fuARCHIVE_LIST | head -1)
	fi
	if [ -z "${myARCHIVE}" ] || [ ! -f "${myARCHIVE}" ];
	  then
	    echo "###### $myBLUE""No backup found in ${myBACKUPDIR}. Name one with '-f'.""$myWHITE"" [ $myRED""NOT OK""$myWHITE ]"
	    echo
	    exit 1
	fi
	fuTMPDIR
	if ! tar tf "${myARCHIVE}" > "${myTMPDIR}/toc" 2>"${myTMPDIR}/toc.err";
	  then
	    echo "###### $myBLUE""Cannot read ${myARCHIVE}.""$myWHITE"" [ $myRED""NOT OK""$myWHITE ]"
	    sed 's/^/###### /' "${myTMPDIR}/toc.err"
	    echo
	    exit 1
	fi
	echo "###### $myBLUE${myARCHIVE}$myWHITE  $(du -h "${myARCHIVE}" | cut -f1), $(grep -c . "${myTMPDIR}/toc") entries"
	if fuHAS "^MANIFEST$";
	  then
	    tar xOf "${myARCHIVE}" MANIFEST | sed 's/^/###### /'
	  else
	    echo "###### $myBLUE""No MANIFEST - this does not look like a backup from update.sh.""$myWHITE"" [ $myRED""WARNING""$myWHITE ]"
	fi
	echo
}

# Ask, unless -y was given
function fuASK () {   # $1 = Frage
	local myANSWER=""
	[ -n "${myCONFIRMED}" ] && return 0
	read -rp "###### $1 (y/n) " myANSWER
	case "${myANSWER}" in
	  y|Y|yes|YES) return 0 ;;
	  *)           return 1 ;;
	esac
}

# What is in there, and which of it should come back?
function fuCHOOSE () {
	echo "### What should be restored?"
	if fuHAS "^rollback.txt$"; then
	  fuASK "Roll the checkout back to the commit before the update?" && myDO_GIT="1"
	fi
	if fuHAS "^tracked.patch$"; then
	  fuASK "Re-apply all your changes to tracked files (tracked.patch)?" && myDO_PATCH="1"
	fi
	if fuHAS "^env$"; then
	  fuASK "Restore the configuration (.env and docker-compose.yml)?" && myDO_CONFIG="1"
	fi
	if fuHAS "^untracked/"; then
	  fuASK "Restore your untracked files?" && myDO_UNTRACKED="1"
	fi
	if fuHAS "^data/"; then
	  fuASK "Restore the files from data/ (certificates, uuid, host keys)?" && myDO_DATA="1"
	fi
	if fuHAS_OPENSEARCH; then
	  fuASK "Import the OpenSearch Dashboards objects and the ISM policy? T-Pot has to run for that." && myDO_OPENSEARCH="1"
	fi
	echo
	if [ -z "${myDO_GIT}${myDO_CONFIG}${myDO_PATCH}${myDO_UNTRACKED}${myDO_DATA}${myDO_OPENSEARCH}" ];
	  then
	    echo "###### $myBLUE""Nothing selected, leaving everything as it is.""$myWHITE"
	    echo
	    exit 0
	fi
}

function fuSTOP_TPOT () {
	echo
	echo -n "### Now stopping T-Pot ... "
	if sudo systemctl stop tpot.service 2>/dev/null;
	  then
	    echo "[ $myGREEN"OK"$myWHITE ]"
	  else
	    echo "[ $myRED""WARNING""$myWHITE ]"
	    echo "###### $myBLUE""No tpot.service, trying docker compose.""$myWHITE"
	    [ -f "${myTPOTDIR}/docker-compose.yml" ] && ( cd "${myTPOTDIR}" && docker compose down ) >/dev/null 2>&1
	fi
}

function fuSTART_TPOT () {
	echo
	echo -n "### Now starting T-Pot ... "
	if sudo systemctl start tpot.service 2>/dev/null;
	  then
	    echo "[ $myGREEN"OK"$myWHITE ]"
	  else
	    echo "[ $myRED""WARNING""$myWHITE ]"
	    echo "###### $myBLUE""Could not start tpot.service, please start T-Pot yourself.""$myWHITE"
	    return 1
	fi
}

# The rollback comes first: a `git reset --hard` puts .env and docker-compose.yml
# back to the state of the commit, so it would overwrite anything done after it.
function fuDO_GIT () {
	local myCOMMIT=""
	[ -z "${myDO_GIT}" ] && return
	echo
	echo "### Rolling the checkout back ..."
	tar xOf "${myARCHIVE}" rollback.txt > "${myTMPDIR}/rollback.txt"
	myCOMMIT=$(tr -d "[:space:]" < "${myTMPDIR}/rollback.txt")
	if [ -z "${myCOMMIT}" ];
	  then
	    echo "###### $myBLUE""rollback.txt is empty, skipping.""$myWHITE"" [ $myRED""WARNING""$myWHITE ]"
	    return
	fi
	if ! git -C "${myTPOTDIR}" cat-file -e "${myCOMMIT}^{commit}" 2>/dev/null;
	  then
	    echo "###### $myBLUE""Commit ${myCOMMIT} is not in ${myTPOTDIR}, skipping.""$myWHITE"" [ $myRED""WARNING""$myWHITE ]"
	    return
	fi
	echo -n "###### $myBLUE Resetting to ${myCOMMIT}.$myWHITE "
	if git -C "${myTPOTDIR}" reset -q --hard "${myCOMMIT}";
	  then
	    echo "[ $myGREEN"OK"$myWHITE ]"
	  else
	    echo " [ $myRED""NOT OK""$myWHITE ]"
	fi
}

function fuDO_CONFIG () {
	local myFILE=""
	[ -z "${myDO_CONFIG}" ] && return
	echo
	echo "### Restoring the configuration ..."
	if tar xf "${myARCHIVE}" -C "${myTMPDIR}" env 2>/dev/null && cp "${myTMPDIR}/env" "${myTPOTDIR}/.env";
	  then
	    echo "###### $myBLUE""Wrote ${myTPOTDIR}/.env.""$myWHITE"" [ $myGREEN""OK""$myWHITE ]"
	  else
	    echo "###### $myBLUE""Could not restore .env.""$myWHITE"" [ $myRED""NOT OK""$myWHITE ]"
	fi
	if fuHAS "^docker-compose.yml$";
	  then
	    if tar xf "${myARCHIVE}" -C "${myTMPDIR}" docker-compose.yml 2>/dev/null \
	       && cp "${myTMPDIR}/docker-compose.yml" "${myTPOTDIR}/docker-compose.yml";
	      then
	        echo "###### $myBLUE""Wrote ${myTPOTDIR}/docker-compose.yml ($(head -1 "${myTPOTDIR}/docker-compose.yml")).""$myWHITE"" [ $myGREEN""OK""$myWHITE ]"
	      else
	        echo "###### $myBLUE""Could not restore docker-compose.yml.""$myWHITE"" [ $myRED""NOT OK""$myWHITE ]"
	    fi
	fi
}

# tracked.patch covers every change to tracked files, so .env and
# docker-compose.yml as well. It describes them against the commit, which is why it
# runs right after the rollback and still before the single-file copies - on a tree
# where .env already holds the changed content it no longer applies. The copies
# afterwards write the same content once more, which costs nothing and covers the
# case where only the configuration was picked.
function fuDO_PATCH () {
	[ -z "${myDO_PATCH}" ] && return
	echo
	echo "### Re-applying your changes to tracked files ..."
	tar xf "${myARCHIVE}" -C "${myTMPDIR}" tracked.patch 2>/dev/null
	if [ ! -s "${myTMPDIR}/tracked.patch" ];
	  then
	    echo "###### $myBLUE""The patch is empty, there was nothing to re-apply.""$myWHITE"" [ $myGREEN""OK""$myWHITE ]"
	    return
	fi
	if git -C "${myTPOTDIR}" apply --check "${myTMPDIR}/tracked.patch" 2>/dev/null;
	  then
	    git -C "${myTPOTDIR}" apply "${myTMPDIR}/tracked.patch" \
	      && echo "###### $myBLUE""Applied.""$myWHITE"" [ $myGREEN""OK""$myWHITE ]"
	    return
	fi
	if git -C "${myTPOTDIR}" apply --3way "${myTMPDIR}/tracked.patch" 2>/dev/null;
	  then
	    echo "###### $myBLUE""Applied with a three-way merge, please review the result.""$myWHITE"" [ $myRED""WARNING""$myWHITE ]"
	    return
	fi
	cp "${myTMPDIR}/tracked.patch" "${myBACKUPDIR}/${myDATE}_tracked.patch"
	echo "###### $myBLUE""The patch does not apply to this tree, most likely because those changes are already in place.""$myWHITE"" [ $myRED""WARNING""$myWHITE ]"
	echo "###### $myBLUE""Left it in ${myBACKUPDIR}/${myDATE}_tracked.patch for you to look at.""$myWHITE"
}

function fuDO_UNTRACKED () {
	[ -z "${myDO_UNTRACKED}" ] && return
	echo
	echo "### Restoring your untracked files ..."
	rm -rf "${myTMPDIR}/untracked"
	if ! tar xf "${myARCHIVE}" -C "${myTMPDIR}" untracked 2>/dev/null;
	  then
	    echo "###### $myBLUE""Could not read them from the archive.""$myWHITE"" [ $myRED""NOT OK""$myWHITE ]"
	    return
	fi
	if ( cd "${myTMPDIR}/untracked" && tar cf - . ) | ( cd "${myTPOTDIR}" && tar xf - );
	  then
	    echo "###### $myBLUE""Restored $(find "${myTMPDIR}/untracked" -type f | wc -l) files.""$myWHITE"" [ $myGREEN""OK""$myWHITE ]"
	  else
	    echo "###### $myBLUE""Could not write them.""$myWHITE"" [ $myRED""NOT OK""$myWHITE ]"
	fi
}

# The files under data/ belong to tpot:tpot (uid/gid 2000) with 0770. Without the
# right modes the containers will not start, so owner and mode come from the archive
# instead of from the caller's umask.
function fuDO_DATA () {
	[ -z "${myDO_DATA}" ] && return
	echo
	echo "### Restoring the files from data/ ..."
	echo -n "###### $myBLUE $(grep -c '^data/' "${myTMPDIR}/toc") entries.$myWHITE "
	if sudo tar xf "${myARCHIVE}" -C "${myTPOTDIR}" -p --numeric-owner --wildcards "data/*" 2>"${myTMPDIR}/data.err";
	  then
	    echo "[ $myGREEN"OK"$myWHITE ]"
	    echo "###### $myBLUE""Owner and mode came from the archive.""$myWHITE"
	  else
	    echo " [ $myRED""NOT OK""$myWHITE ]"
	    sed 's/^/###### /' "${myTMPDIR}/data.err"
	fi
}

# The OpenSearch import needs a running instance - unlike everything else, which
# wants T-Pot stopped. So it runs last, after the start.
function fuDO_OPENSEARCH () {
	local myWAIT=0
	local myOBJ=0
	local myKEEP=""
	local myCODE=""
	local mySEQ=""
	local myTERM=""
	local myQUERY=""
	[ -z "${myDO_OPENSEARCH}" ] && return
	echo
	echo "### Importing the OpenSearch state ..."
	rm -rf "${myTMPDIR}/opensearch"
	tar xf "${myARCHIVE}" -C "${myTMPDIR}" opensearch 2>/dev/null
	echo -n "###### $myBLUE Waiting for OpenSearch Dashboards on ${myDASHBOARDS} $myWHITE"
	while [ "${myWAIT}" -lt "${myDASHBOARDS_TIMEOUT}" ];
	  do
	    curl -s -f -o /dev/null --connect-timeout 3 "${myDASHBOARDS}/api/status" && break
	    sleep 5
	    myWAIT=$((myWAIT+5))
	    echo -n "."
	done
	if ! curl -s -f -o /dev/null "${myDASHBOARDS}/api/status";
	  then
	    echo " [ $myRED""NOT OK""$myWHITE ]"
	    # The files sit in the working directory, which is about to vanish - for the
	    # manual route they have to stay, and the commands have to name the real path.
	    myKEEP="${myBACKUPDIR}/${myDATE}_opensearch"
	    mkdir -p "${myKEEP}" && cp -a "${myTMPDIR}/opensearch/." "${myKEEP}/" 2>/dev/null
	    echo "###### $myBLUE""OpenSearch Dashboards did not come up in ${myWAIT}s. The files are in ${myKEEP}, run these once it does:""$myWHITE"
	    if [ -s "${myKEEP}/osd_export.ndjson" ];
	      then
	        echo "######   $myBLUE""curl -X POST '${myDASHBOARDS}/api/saved_objects/_import?overwrite=true' -H 'osd-xsrf: true' --form file=@${myKEEP}/osd_export.ndjson""$myWHITE"
	    fi
	    if [ -s "${myKEEP}/ism_policy_tpot.json" ];
	      then
	        echo "######   $myBLUE""curl '${myOS}/_plugins/_ism/policies/tpot'   # note _seq_no and _primary_term, if the policy exists""$myWHITE"
	        echo "######   $myBLUE""curl -X PUT '${myOS}/_plugins/_ism/policies/tpot?if_seq_no=<_seq_no>&if_primary_term=<_primary_term>' -H 'Content-Type: application/json' -d @${myKEEP}/ism_policy_tpot.json""$myWHITE"
	        echo "######   $myBLUE""(leave out '?if_seq_no=...&if_primary_term=...' if the GET above returned 404)""$myWHITE"
	    fi
	    return 1
	fi
	echo " [ $myGREEN"OK"$myWHITE ] after ${myWAIT}s"
	if [ -s "${myTMPDIR}/opensearch/osd_export.ndjson" ];
	  then
	    echo -n "###### $myBLUE Importing the OpenSearch Dashboards objects.$myWHITE "
	    if curl -s -f -X POST "${myDASHBOARDS}/api/saved_objects/_import?overwrite=true" \
	         -H "osd-xsrf: true" --form file=@"${myTMPDIR}/opensearch/osd_export.ndjson" \
	         -o "${myTMPDIR}/import.json";
	      then
	        myOBJ=$(sed -n 's/.*"successCount":\([0-9]*\).*/\1/p' "${myTMPDIR}/import.json")
	        if grep -q '"success":true' "${myTMPDIR}/import.json";
	          then
	            echo "[ $myGREEN"OK"$myWHITE ] ${myOBJ:-0} objects"
	          else
	            echo " [ $myRED""WARNING""$myWHITE ] ${myOBJ:-0} objects, errors reported"
	            sed 's/^/###### /' "${myTMPDIR}/import.json" | head -5
	        fi
	      else
	        echo " [ $myRED""NOT OK""$myWHITE ]"
	    fi
	fi
	if [ -s "${myTMPDIR}/opensearch/ism_policy_tpot.json" ];
	  then
	    echo -n "###### $myBLUE Putting the ISM policy back.$myWHITE "
	    # update.sh stored it ready to be put back. Logstash creates the policy on
	    # every start, so it usually exists already - and then OpenSearch only takes
	    # the PUT with the _seq_no and _primary_term of the current version.
	    myCODE=$(curl -s -o "${myTMPDIR}/ism_current.json" -w "%{http_code}" "${myOS}/_plugins/_ism/policies/tpot")
	    case "${myCODE}" in
	      200)
	        mySEQ=$(sed -n 's/.*"_seq_no":\([0-9]*\).*/\1/p' "${myTMPDIR}/ism_current.json")
	        myTERM=$(sed -n 's/.*"_primary_term":\([0-9]*\).*/\1/p' "${myTMPDIR}/ism_current.json")
	        [ -n "${mySEQ}" ] && [ -n "${myTERM}" ] && myQUERY="?if_seq_no=${mySEQ}&if_primary_term=${myTERM}"
	        ;;
	      404)
	        myQUERY=""
	        ;;
	      *)
	        myCODE="unreachable"
	        ;;
	    esac
	    if [ "${myCODE}" = "200" ] && [ -z "${myQUERY}" ];
	      then
	        echo " [ $myRED""WARNING""$myWHITE ]"
	        echo "###### $myBLUE""Could not read the version of the existing ISM policy, the file is in the archive under opensearch/.""$myWHITE"
	    elif [ "${myCODE}" = "unreachable" ];
	      then
	        echo " [ $myRED""WARNING""$myWHITE ]"
	        echo "###### $myBLUE""OpenSearch did not answer on ${myOS}, the file is in the archive under opensearch/.""$myWHITE"
	    elif curl -s -f -X PUT "${myOS}/_plugins/_ism/policies/tpot${myQUERY}" \
	         -H "Content-Type: application/json" \
	         -d @"${myTMPDIR}/opensearch/ism_policy_tpot.json" -o /dev/null;
	      then
	        echo "[ $myGREEN"OK"$myWHITE ]"
	      else
	        echo " [ $myRED""WARNING""$myWHITE ]"
	        echo "###### $myBLUE""Could not put the ISM policy back, the file is in the archive under opensearch/.""$myWHITE"
	    fi
	fi
}

################
# Main section #
################

while getopts ":lf:yh" opt; do
  case "$opt" in
    l)
      myLIST="1"
      ;;
    f)
      myARCHIVE="${OPTARG}"
      ;;
    y)
      myCONFIRMED="y"
      ;;
    h|\?)
      fuPRINT_HELP
      ;;
    :)
      echo "Option -${OPTARG} requires an argument."
      fuPRINT_HELP
      ;;
  esac
done

echo "$myRESTORER"

fuTMPDIR
[ -n "${myLIST}" ] && fuLIST

if [ ! -d "${myTPOTDIR}" ];
  then
    echo "###### $myBLUE""There is no ${myTPOTDIR}.""$myWHITE"" [ $myRED""NOT OK""$myWHITE ]"
    echo
    exit 1
fi

fuPICK_ARCHIVE

if [ -n "${myCONFIRMED}" ];
  then
    echo "### Restoring everything from this archive."
    fuHAS "^rollback.txt$"   && myDO_GIT="1"
    fuHAS "^env$"            && myDO_CONFIG="1"
    fuHAS "^tracked.patch$"  && myDO_PATCH="1"
    fuHAS "^untracked/"      && myDO_UNTRACKED="1"
    fuHAS "^data/"           && myDO_DATA="1"
    fuHAS_OPENSEARCH         && myDO_OPENSEARCH="1"
  else
    fuCHOOSE
fi

# Phase 1 - everything that needs T-Pot stopped. If only the OpenSearch import
# was picked there is nothing to do here and T-Pot can keep running.
if [ -n "${myDO_GIT}${myDO_CONFIG}${myDO_PATCH}${myDO_UNTRACKED}${myDO_DATA}" ];
  then
    fuSTOP_TPOT
fi
fuDO_GIT
fuDO_PATCH
fuDO_CONFIG
fuDO_UNTRACKED
fuDO_DATA

# Phase 2 - the OpenSearch import needs a running instance
if [ -n "${myDO_OPENSEARCH}" ];
  then
    # If T-Pot kept running there is nothing to start
    if [ -n "${myDO_GIT}${myDO_CONFIG}${myDO_PATCH}${myDO_UNTRACKED}${myDO_DATA}" ];
      then
        fuSTART_TPOT
    fi
    fuDO_OPENSEARCH
  else
    echo
    echo "### Done. You can now start T-Pot using 'systemctl start tpot' or 'docker compose up -d'."
fi
echo
