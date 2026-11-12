FROM opensearchproject/opensearch:3.9.0
#
# Include dist
COPY dist/opensearch.yml /usr/share/opensearch/config/opensearch.yml
#
# Remove plugins T-Pot does not use. This keeps the heap footprint small and removes
# the security plugin (T-Pot runs the cluster on the internal network only, nginx
# is the authenticated entry point).
# Order matters, plugins that extend others have to go first.
USER root
RUN cd /usr/share/opensearch && \
    for myPLUGIN in opensearch-skills \
                    opensearch-flow-framework \
                    opensearch-neural-search \
                    opensearch-search-relevance \
                    opensearch-ml \
                    opensearch-knn \
                    opensearch-ltr \
                    opensearch-ubi \
                    opensearch-security-analytics \
                    opensearch-anomaly-detection \
                    opensearch-cross-cluster-replication \
                    opensearch-performance-analyzer \
                    opensearch-security; \
      do \
        bin/opensearch-plugin remove --purge "$myPLUGIN" || exit 1; \
    done && \
    rm -rf /usr/share/opensearch/config/opensearch-security \
           /usr/share/opensearch/config/opensearch-performance-analyzer && \
    sed -i '/opensearch-performance-analyzer\/opensearch_security.policy/d; /jdk.attach.allowAttachSelf/d; /jdk.attach\/sun.tools.attach/d' \
           /usr/share/opensearch/config/jvm.options && \
#
# Setup user, groups and configs (T-Pot data is owned by uid / gid 2000)
    groupmod -g 2000 opensearch && \
    usermod -u 2000 -g 2000 opensearch && \
    chown -R opensearch:opensearch /usr/share/opensearch
#
# Healthcheck
HEALTHCHECK --retries=10 CMD curl -s -f -XGET 'http://127.0.0.1:9200/_cluster/health?wait_for_status=yellow&timeout=5s' || exit 1
#
# Start OpenSearch (aarch64 needs SVE disabled for the bundled JDK)
USER opensearch:opensearch
ENTRYPOINT ["/bin/bash", "-c", "if [ \"$(arch)\" = \"aarch64\" ]; then export _JAVA_OPTIONS=\"-XX:UseSVE=0\"; fi && exec ./opensearch-docker-entrypoint.sh opensearch"]
