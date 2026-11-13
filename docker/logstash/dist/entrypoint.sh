#!/bin/bash

# Let's ensure normal operation on exit or if interrupted ...
function fuCLEANUP {
  exit 0
}
trap fuCLEANUP EXIT

# Source ENVs from file ...
if [ -f "/data/tpot/etc/compose/tpot_environment" ];
  then
    echo "Found .env, now exporting ..."
    set -o allexport
    source "/data/tpot/etc/compose/tpot_environment"
    LS_SSL_VERIFICATION="${LS_SSL_VERIFICATION:-full}"
    set +o allexport
fi

# Identify requests to Listbot by user agent and T-Pot UUID (only if the UUID is valid)
myLISTBOTUA="listbot"
myTPOTUUID="${HONEY_UUID:-$(cat /data/uuid 2>/dev/null)}"
if [[ ! "$myTPOTUUID" =~ ^[0-9a-fA-F-]{36}$ ]];
  then
    echo "No valid T-Pot UUID found, sending requests to Listbot without X-TPot-UUID header."
    myTPOTUUID=""
fi
myCURLOPTS=(-A "$myLISTBOTUA")
myWGETOPTS=(--user-agent="$myLISTBOTUA")
if [ -n "$myTPOTUUID" ];
  then
    myCURLOPTS+=(-H "X-TPot-UUID: $myTPOTUUID")
    myWGETOPTS+=(--header="X-TPot-UUID: $myTPOTUUID")
fi

# Check internet availability 
function fuCHECKINET () {
mySITES=$1
error=0
for i in $mySITES;
  do
    curl "${myCURLOPTS[@]}" --connect-timeout 5 -Is $i 2>&1 > /dev/null
      if [ $? -ne 0 ];
        then
          let error+=1
      fi;
  done;
  echo $error
}

# Translation maps are cached in /data/logstash/listbot and only downloaded if missing or >= 24h old
myLISTBOTURL="https://listbot.sicherheitstacho.eu"
myLISTBOTCACHE="/data/logstash/listbot"
myLISTBOTFILES="cve.yaml.bz2 iprep.yaml.bz2"

# Check if a cached translation map is missing, empty or 24h and older
function fuNEEDSUPDATE () {
  local myFILE=$1
  if [ ! -s "$myFILE" ] || [ -n "$(find "$myFILE" -mmin +1439)" ];
    then
      return 0
  fi
  return 1
}

# Fallback in case tpotinit did not create the cache folder
if [ ! -d "$myLISTBOTCACHE" ];
  then
    mkdir -p "$myLISTBOTCACHE"
    chmod 770 "$myLISTBOTCACHE"
fi

# Check for connectivity only if needed and download latest translation maps
myCHECK=""
for myFILE in $myLISTBOTFILES;
  do
    if ! fuNEEDSUPDATE "$myLISTBOTCACHE/$myFILE";
      then
        echo "Cached $myFILE is current (< 24h), skipping download."
        continue
    fi
    if [ -z "$myCHECK" ];
      then
        myCHECK=$(fuCHECKINET "listbot.sicherheitstacho.eu")
    fi
    if [ "$myCHECK" != "0" ];
      then
        echo "Cannot reach Listbot, skipping download of $myFILE."
        continue
    fi
    echo "Downloading latest $myFILE from Listbot."
    if wget "${myWGETOPTS[@]}" -q --no-use-server-timestamps --timeout=30 --tries=3 -O "$myLISTBOTCACHE/$myFILE.tmp" "$myLISTBOTURL/$myFILE" && \
       bunzip2 -t "$myLISTBOTCACHE/$myFILE.tmp" 2>/dev/null;
      then
        mv -f "$myLISTBOTCACHE/$myFILE.tmp" "$myLISTBOTCACHE/$myFILE"
        chmod 770 "$myLISTBOTCACHE/$myFILE"
      else
        echo "Download of $myFILE failed, keeping cached version if present."
        rm -f "$myLISTBOTCACHE/$myFILE.tmp"
    fi
done

# Provide translation maps where Logstash expects them, fall back to image defaults
for myFILE in $myLISTBOTFILES;
  do
    if [ -s "$myLISTBOTCACHE/$myFILE" ] && \
       bunzip2 -c "$myLISTBOTCACHE/$myFILE" > "/etc/listbot/${myFILE%.bz2}.tmp";
      then
        mv -f "/etc/listbot/${myFILE%.bz2}.tmp" "/etc/listbot/${myFILE%.bz2}"
        echo "Using cached $myFILE."
      else
        rm -f "/etc/listbot/${myFILE%.bz2}.tmp"
        echo "No usable cached $myFILE, starting Logstash with translation map from image."
    fi
done

# GeoIP databases (HIVE / STANDARD only), see MAXMIND_* in T-Pot .env
myGEOIPDIR="/data/logstash/geoip"
myGEOIPCONF="/etc/logstash/tpot_geoip.conf"
myGEOIPCITY="${MAXMIND_CITY_EDITION:-GeoLite2-City}"
myGEOIPASN="${MAXMIND_ASN_EDITION:-GeoLite2-ASN}"
# Seconds between update checks, TPOT_GEOIP_INTERVAL is only meant for testing
myGEOIPINTERVAL="${TPOT_GEOIP_INTERVAL:-86400}"
[[ "$myGEOIPINTERVAL" =~ ^[0-9]+$ ]] && [ "$myGEOIPINTERVAL" -ge 60 ] || myGEOIPINTERVAL=86400
myGEOIPMAXAGE=14

# Check the MaxMind settings, they end up in a geoipupdate config file
function fuGEOIPVALID () {
  [ -n "$MAXMIND_ACCOUNT_ID" ] && [ -n "$MAXMIND_LICENSE_KEY" ] && \
  [[ "$MAXMIND_ACCOUNT_ID" =~ ^[0-9]+$ ]] && \
  [[ "$MAXMIND_LICENSE_KEY" =~ ^[A-Za-z0-9_]+$ ]] && \
  [[ "$myGEOIPCITY" =~ ^[A-Za-z0-9-]+$ ]] && \
  [[ "$myGEOIPASN" =~ ^[A-Za-z0-9-]+$ ]]
}

# Download changed databases, geoipupdate verifies and replaces them atomically
function fuGEOIPUPDATE () {
  local myCONF
  local myRC
  mkdir -p "$myGEOIPDIR"
  chmod 770 "$myGEOIPDIR"
  # mktemp creates the file with 0600, the license key is not readable for others
  myCONF=$(mktemp /tmp/GeoIP.conf.XXXXXX) || return 1
  printf 'AccountID %s\nLicenseKey %s\nEditionIDs %s %s\nRetryFor 2m\n' \
    "$MAXMIND_ACCOUNT_ID" "$MAXMIND_LICENSE_KEY" "$myGEOIPCITY" "$myGEOIPASN" > "$myCONF"
  geoipupdate -f "$myCONF" -d "$myGEOIPDIR"
  myRC=$?
  rm -f "$myCONF"
  return $myRC
}

# Generate tpot_geoip.conf for the available databases. Returns 0 only if it differs from
# the current file. With "check" the current file is left untouched, otherwise replaced.
function fuGEOIPRENDER () {
  local myMODE="$1"
  local myCITYDB="$myGEOIPDIR/$myGEOIPCITY.mmdb"
  local myASNDB="$myGEOIPDIR/$myGEOIPASN.mmdb"
  local myNEW
  local myVERSION
  myNEW=$(mktemp "$myGEOIPCONF.XXXXXX") || return 1
  {
    echo "# GeoIP enrichment for the HIVE / STANDARD pipelines (logstash, http_input)."
    echo "# Generated by entrypoint.sh from the databases in $myGEOIPDIR on start;"
    echo "# Logstash is restarted when the databases change. Do not edit."
    echo "#"
  } > "$myNEW"
  if [ -s "$myCITYDB" ] && [ -s "$myASNDB" ];
    then
      # The version changes with the databases, which is how updates are detected
      myVERSION=$(cat "$myCITYDB" "$myASNDB" | sha256sum | cut -c1-16)
      cat >> "$myNEW" << EOF
# Databases: $myGEOIPCITY.mmdb, $myGEOIPASN.mmdb (version $myVERSION)
filter {
  if [src_ip] {
    geoip {
      cache_size => 10000
      source => "src_ip"
      database => "$myCITYDB"
    }
    geoip {
      cache_size => 10000
      source => "src_ip"
      database => "$myASNDB"
    }
  }
  if [t-pot_ip_ext] {
    geoip {
      cache_size => 10000
      source => "t-pot_ip_ext"
      target => "geoip_ext"
      database => "$myCITYDB"
    }
    geoip {
      cache_size => 10000
      source => "t-pot_ip_ext"
      target => "geoip_ext"
      database => "$myASNDB"
    }
  }
}
EOF
    else
      echo "# GeoIP enrichment disabled: no GeoIP databases available." >> "$myNEW"
  fi
  if cmp -s "$myNEW" "$myGEOIPCONF";
    then
      rm -f "$myNEW"
      return 1
  fi
  if [ "$myMODE" == "check" ];
    then
      rm -f "$myNEW"
      return 0
  fi
  chmod 644 "$myNEW"
  mv -f "$myNEW" "$myGEOIPCONF"
  return 0
}

# Report whether GeoIP enrichment is active and warn about outdated databases
function fuGEOIPSTATUS () {
  local myDB
  if ! grep -q "geoip {" "$myGEOIPCONF";
    then
      echo "WARNING: GeoIP enrichment is DISABLED, events get no geoip / geoip_ext fields (Attack Map, Dashboards)."
      return
  fi
  for myDB in "$myGEOIPDIR/$myGEOIPCITY.mmdb" "$myGEOIPDIR/$myGEOIPASN.mmdb";
    do
      echo "GeoIP database $(basename "$myDB") from $(date -u -r "$myDB" '+%Y-%m-%d')."
      if [ -n "$(find "$myDB" -mtime +$myGEOIPMAXAGE)" ];
        then
          echo "WARNING: GeoIP database $(basename "$myDB") is older than $myGEOIPMAXAGE days."
      fi
  done
}

# Distributed T-Pot installation needs a different pipeline config
if [ "$TPOT_TYPE" == "SENSOR" ];
  then
    echo
    echo "Distributed T-Pot setup, sending T-Pot logs to $TPOT_HIVE_IP."
    echo
    echo "T-Pot type: $TPOT_TYPE"
    echo "Hive IP: $TPOT_HIVE_IP"
    echo "SSL verification: $LS_SSL_VERIFICATION"
    echo
   # Ensure correct file permissions for private keyfile or SSH will ask for password
    cp /usr/share/logstash/config/pipelines_sensor.yml /usr/share/logstash/config/pipelines.yml
fi

if [ "$TPOT_TYPE" != "SENSOR" ];
  then
    echo
    echo "This is a T-Pot STANDARD / HIVE installation."
    echo
    echo "T-Pot type: $TPOT_TYPE"
    echo

    # Index management is happening through ISM (OpenSearch Index State Management).
    # The index template is put on every start, so changes to tpot-template.json are
    # applied to the next daily index.
    myOS="http://opensearch:9200"
    until curl -s -f -o /dev/null "${myOS}/_cluster/health?wait_for_status=yellow&timeout=5s";
      do
        echo "Waiting for OpenSearch ..."
        sleep 5
    done
    echo -n "Putting T-Pot index template on OpenSearch: "
    curl -s -XPUT "${myOS}/_index_template/tpot" -H 'Content-Type: application/json' --data-binary @/etc/logstash/tpot-template.json
    echo
    # The ISM policy is only put if missing, retention changes made by the user are kept.
    myTPOTISM=$(curl -s -o /dev/null -w "%{http_code}" "${myOS}/_plugins/_ism/policies/tpot")
    if [ "$myTPOTISM" == "404" ];
      then
        echo -n "T-Pot ISM policy not found on OpenSearch, putting it on OpenSearch now: "
        curl -s -XPUT "${myOS}/_plugins/_ism/policies/tpot" -H 'Content-Type: application/json' --data-binary @/etc/logstash/tpot-ism-policy.json
        echo
      else
        echo "T-Pot ISM policy already configured (HTTP $myTPOTISM)."
    fi
    # The policy's ism_template only applies to indices created after the policy, so
    # attach it to existing logstash-* indices that are not managed yet (e.g. after a
    # restore). Indices that are already managed are skipped by OpenSearch.
    echo -n "Attaching T-Pot ISM policy to unmanaged logstash-* indices: "
    curl -s -XPOST "${myOS}/_plugins/_ism/add/logstash-*" -H 'Content-Type: application/json' -d '{ "policy_id": "tpot" }' | grep -o '"updated_indices":[0-9]*' || echo "none"

    # GeoIP enrichment happens only here (HIVE / STANDARD), sensors ship events without it.
    # Databases are downloaded with geoipupdate into $myGEOIPDIR and tpot_geoip.conf is
    # generated from them on start. Changed databases restart Logstash instead of a
    # pipeline reload: a reload briefly holds the large translate dictionaries twice,
    # which exceeds the default heap.
    echo
    if fuGEOIPVALID;
      then
        echo "Updating GeoIP databases ($myGEOIPCITY, $myGEOIPASN) ..."
        fuGEOIPUPDATE || echo "GeoIP database update failed, using cached databases if present."
      elif [ -n "$MAXMIND_ACCOUNT_ID$MAXMIND_LICENSE_KEY" ];
        then
          echo "WARNING: Invalid MaxMind settings (MAXMIND_ACCOUNT_ID / MAXMIND_LICENSE_KEY / MAXMIND_*_EDITION), GeoIP databases are not updated."
      else
        echo "No MaxMind account configured (MAXMIND_ACCOUNT_ID / MAXMIND_LICENSE_KEY), GeoIP databases are not updated."
    fi
    fuGEOIPRENDER
    fuGEOIPSTATUS
    if fuGEOIPVALID;
      then
        # Background loop: survives the exec below, so $$ is the Logstash process then.
        # geoipupdate only downloads changed databases. On a change Logstash shuts down
        # gracefully and the container restarts (restart: always), file inputs resume
        # from their sincedb and sensors retry.
        (
          while true;
            do
              sleep "$myGEOIPINTERVAL"
              fuGEOIPUPDATE || echo "GeoIP database update failed, keeping current databases."
              if fuGEOIPRENDER check;
                then
                  echo "GeoIP databases changed, restarting Logstash to use them."
                  kill -TERM $$
                  exit 0
              fi
              fuGEOIPSTATUS
          done
        ) &
    fi
fi
echo

ARCH=$(arch)
if [ "$ARCH" = "aarch64" ]; then
  export _JAVA_OPTIONS="-XX:UseSVE=0";
fi
exec /usr/share/logstash/bin/logstash --config.reload.automatic
