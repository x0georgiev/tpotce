#!/usr/bin/env bash

# Backup all OpenSearch Dashboards objects
# Make sure OpenSearch Dashboards is available
myDASHBOARDS="http://127.0.0.1:64296/dashboards"
if ! curl -s -f -o /dev/null "${myDASHBOARDS}/api/status";
  then
    echo "### OpenSearch Dashboards is not available."
    exit 1
  else
    echo "### OpenSearch Dashboards is available, now continuing."
    echo
fi

# Export OpenSearch Dashboards config
echo "### Exporting OpenSearch Dashboards config."
curl -s -X POST "${myDASHBOARDS}/api/saved_objects/_export" \
  -H "osd-xsrf: true" \
  -H "Content-Type: application/json" \
  -d '{
    "type": ["config", "index-pattern", "visualization", "dashboard", "search", "query", "url"],
    "excludeExportDetails": true
  }' \
  -o osd_export.ndjson

echo
echo "### Zipping OpenSearch Dashboards config."
zip osd_export.ndjson.zip osd_export.ndjson

echo
echo "### Moving OpenSearch Dashboards config and zip to ../etc/objects/"
mv osd_export.* ../etc/objects
