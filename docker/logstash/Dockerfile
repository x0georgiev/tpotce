FROM ubuntu:24.04
ENV DEBIAN_FRONTEND=noninteractive
ENV LS_VER=9.3.5
#
# Include dist
COPY dist/ /root/dist/
#
# Install packages
RUN apt-get update -y && \
    apt-get upgrade -y && \
    apt-get install -y \
    		 adduser \
             bash \
             bzip2 \
             curl \
             geoipupdate \
             wget && \
#
# Determine arch, get and install packages
    ARCH=$(arch) && \
    if [ "$ARCH" = "x86_64" ]; then LS_ARCH="amd64"; export _JAVA_OPTIONS=""; fi && \
    if [ "$ARCH" = "aarch64" ]; then LS_ARCH="arm64"; export _JAVA_OPTIONS="-XX:UseSVE=0"; fi && \
    echo "$ARCH" && \
    mkdir -p /etc/listbot && \
    cd /etc/listbot && \
    wget -q --user-agent=listbot https://listbot.sicherheitstacho.eu/cve.yaml.bz2 && \
    wget -q --user-agent=listbot https://listbot.sicherheitstacho.eu/iprep.yaml.bz2 && \
    bunzip2 *.bz2 && \
    cd /root/dist/ && \
    wget -q https://artifacts.elastic.co/downloads/logstash/logstash-oss-$LS_VER-$LS_ARCH.deb && \
    dpkg -i logstash-oss-$LS_VER-$LS_ARCH.deb && \
#
# Add and move files
    cd /root/dist/ && \
    cp entrypoint.sh /usr/bin/ && \
    chmod u+x /usr/bin/entrypoint.sh && \
    mkdir -p /usr/share/logstash/config && \
    cp logstash.conf /etc/logstash/ && \
    cp http_input.conf /etc/logstash/ && \
    cp http_output.conf /etc/logstash/ && \
    cp tpot_geoip.conf /etc/logstash/ && \
    cp pipelines.yml /usr/share/logstash/config/pipelines.yml && \
    cp pipelines_sensor.yml /usr/share/logstash/config/pipelines_sensor.yml && \
    cp tpot-template.json /etc/logstash/ && \
    cp tpot-ism-policy.json /etc/logstash/ && \
    cd /usr/share/logstash && \
    bin/logstash-plugin update logstash-filter-translate && \
	bin/logstash-plugin install logstash-output-syslog && \
    bin/logstash-plugin install --version 2.1.1 logstash-output-opensearch && \
# Remove the Elasticsearch plugins T-Pot does not use. The OSS distribution has no
# X-Pack, so nothing needs logstash-output-elasticsearch.
    bin/logstash-plugin remove logstash-filter-elasticsearch \
                               logstash-input-elastic_serverless_forwarder \
                               logstash-input-elasticsearch \
                               logstash-output-elasticsearch && \
# Remove the GeoLite2 databases bundled with logstash-filter-geoip, so the image ships
# no (outdated) MaxMind data. The HIVE downloads current databases with geoipupdate.
    rm -f vendor/bundle/jruby/*/gems/logstash-filter-geoip-*/vendor/*.mmdb && \
    rm /etc/logstash/pipelines.yml && \
    rm /etc/logstash/logstash.yml && \
#
# Setup user, groups and configs
    groupmod -g 2000 logstash && \
    usermod -u 2000 logstash && \
    chown -R logstash:logstash /etc/listbot \
        /var/log/logstash/ \
        /var/lib/logstash \
        /usr/share/logstash/data \
        /usr/share/logstash/config/pipelines* && \
# The entrypoint rewrites tpot_geoip.conf (atomically, so it needs the folder as well)
    chown logstash:logstash /etc/logstash /etc/logstash/tpot_geoip.conf && \
    chmod 755 /usr/bin/entrypoint.sh && \
#
# Clean up
    apt-get autoremove -y --purge && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/* \
        /tmp/* /var/tmp/* \
        /root/.cache \
        /root/*
#
# Healthcheck
HEALTHCHECK --retries=10 CMD curl -s -XGET 'http://127.0.0.1:9600'
#
# Start logstash
USER logstash:logstash
CMD ["entrypoint.sh"]
