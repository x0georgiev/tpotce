#!/bin/bash
# Make sure OpenSearch is available
myOS="http://127.0.0.1:64298/"
myOSSTATUS=$(curl -s -XGET ''$myOS'_cluster/health' | jq -r '.status' | grep -c -E "green|yellow")
if ! [ "$myOSSTATUS" = "1" ]
  then
    echo "### OpenSearch is not available."
    exit 1
  else
    echo "### OpenSearch is available, now continuing."
    echo
fi

function fuMYTOPIPS {
curl -s -XGET $myOS"logstash-*/_search" -H 'Content-Type: application/json' -d'
{
  "aggs": {
    "ips": {
      "terms": { "field": "src_ip.keyword", "size": 100 }
    }
  },
  "size" : 0
}'
}

echo "### Aggregating top 100 source IPs in OpenSearch"
fuMYTOPIPS | jq '.aggregations.ips.buckets[].key' | tr -d '"'
