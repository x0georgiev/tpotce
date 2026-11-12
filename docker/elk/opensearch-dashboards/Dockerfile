FROM opensearchproject/opensearch-dashboards:3.9.0
#
# Include dist
COPY dist/opensearch_dashboards.yml /usr/share/opensearch-dashboards/config/opensearch_dashboards.yml
#
# Healthcheck
HEALTHCHECK --retries=10 CMD curl -f -s -XGET 'http://127.0.0.1:5601/api/status'
#
# Start OpenSearch Dashboards
STOPSIGNAL SIGKILL
