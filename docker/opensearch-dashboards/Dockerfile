FROM opensearchproject/opensearch-dashboards:3.9.0
#
# Include dist
COPY dist/opensearch_dashboards.yml /usr/share/opensearch-dashboards/config/opensearch_dashboards.yml
#
# Remove plugins whose OpenSearch backend plugins are not shipped by T-Pot (see
# docker/opensearch/Dockerfile), otherwise they log errors or break their apps.
USER root
RUN cd /usr/share/opensearch-dashboards && \
    for myPLUGIN in securityDashboards \
                    assistantDashboards \
                    investigationDashboards \
                    mlCommonsDashboards \
                    flowFrameworkDashboards \
                    searchRelevanceDashboards \
                    securityAnalyticsDashboards \
                    anomalyDetectionDashboards; \
      do \
        bin/opensearch-dashboards-plugin remove "$myPLUGIN" --allow-root || exit 1; \
    done && \
#
# Keep the Node.js heap within the container memory limit
    echo "--max-old-space-size=640" >> config/node.options && \
#
# Setup user, groups and configs
    groupmod -g 2000 opensearch-dashboards && \
    usermod -u 2000 -g 2000 opensearch-dashboards && \
    chown -R opensearch-dashboards:opensearch-dashboards /usr/share/opensearch-dashboards
#
# Healthcheck (Dashboards is served below the /dashboards base path)
HEALTHCHECK --retries=10 CMD curl -s -f -XGET 'http://127.0.0.1:5601/dashboards/api/status' || exit 1
#
# Start OpenSearch Dashboards
STOPSIGNAL SIGKILL
USER opensearch-dashboards:opensearch-dashboards
