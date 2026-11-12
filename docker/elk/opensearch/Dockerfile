FROM opensearchproject/opensearch:3.9.0
#
# Include dist
COPY dist/opensearch.yml /usr/share/opensearch/config/opensearch.yml
#
# Healthcheck
HEALTHCHECK --retries=10 CMD curl -s -XGET 'http://127.0.0.1:9200/_cluster/health'
