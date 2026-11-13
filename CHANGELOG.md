# Release Notes / Changelog
## Unreleased
T-Pot is built on **OpenSearch** and **OpenSearch Dashboards**.

## Updates
* **OpenSearch 3.9.0** (`opensearch`) stores all events, **OpenSearch Dashboards 3.9.0** (`opensearch-dashboards`) visualizes them at `https://<host>:64297/dashboards/`. Security plugins and several unused heavy plugins (ML, k-NN, neural search, security analytics, anomaly detection, performance analyzer, ...) are removed from the images.
* **Logstash** is the Apache-2.0 licensed OSS distribution (`logstash-oss`, no X-Pack) and ships events using the `logstash-output-opensearch` plugin; all bundled Elasticsearch plugins are removed.
* **GeoIP** enrichment moved to the Hive / Standard installation: sensors no longer enrich events, the Hive adds `geoip` / `geoip_ext` to local and sensor events. The image ships no GeoIP data anymore; Logstash downloads the MaxMind databases with `geoipupdate` (set `MAXMIND_ACCOUNT_ID` / `MAXMIND_LICENSE_KEY` in `.env`), checks for updates every 24h and restarts when they change. Without an account GeoIP enrichment is disabled; `update.sh` adds the new settings to existing `.env` files.
* **Retention** is handled by the OpenSearch ISM policy `tpot` (30 days).
* **Dashboards** are classic OpenSearch Dashboards visualizations (`docker/tpotinit/dist/etc/objects/osd_export.ndjson`), imported by `tpotinit`, which also keeps the index pattern's field list current.
* **Attack Map** data server talks to OpenSearch through a small client shim.
* **Elasticvue** has been removed, use OpenSearch Dashboards `Dev Tools` and `Index Management` instead.

# T-Pot 24.04.1
T-Pot 24.04.1 brings significant updates and exciting new honeypot additions, especially the LLM-based honeypots **Beelzebub** and **Galah**!

## New Features
* **Beelzebub** (SSH) and **Galah** (HTTP) are the first LLM-based honeypots included in T-Pot (requires Ollama installation or a ChatGPT subscription).
* **Go-Pot** a HTTP tarpit designed to maximize bot misery by slowly feeding them an infinite stream of fake secrets.
* **Honeyaml** a configurable API server honeypot even supporting JWT-based HTTP bearer/token authentication.
* **H0neytr4p** a HTTP/S honeypot capable of emulating vulnerabilities using configurable traps.
* **Miniprint** a medium-interaction printer honeypot.
* **RDPHoneypot** a Remote Desktop honeypot for RDP connection and credential telemetry.

## Updates
* **Honeypots** were updated to their latest pushed code and / or releases.
* **Editions** have been re-introduced. You can now additionally choose to install T-Pot as **Mini**, **LLM** and **Tarpit** edition.
* **Attack Map** has been updated to 2.2.6 including support for all new honeypots.
* **Elastic Stack** has been upgrade to 8.16.1.
* **Cyberchef** has been updated to the latest release.
* **Elasticvue** has been updated to 1.1.0.
* **Suricata** has been updated to 7.0.7, now supporting JA4 hashes.
* Most honeypots now use **PyInstaller** (for Python) and **Scratch** (for Go) to minimize Docker image sizes.
* All new honeypots have been integrated with **Kibana**, featuring dedicated dashboards and visualizations.
* **Github Container Registry** is now the default container registry for the T-Pot configuration file `.env`.
* Compatibility tested with **Alma 9.5**, **Fedora 41**, **Rocky 9.5**, and **Ubuntu 24.04.1**, with updated supported ISO links.
* Docker images now use **Alpine 3.20** or **Scratch** wherever possible.
* Updates for `24.04.1` images will be provided continuously through Docker image updates.
* **Ddospot** has been moved from the Hive / Sensor installation to the Tarpit installation.

## Breaking Changes  
### NGINX  
- The container no longer runs in host mode, requiring changes to the `docker-compose.yml` and related services.  
- To avoid confusion and downtime, the `24.04.1` tag for Docker images has been introduced.  
- **Important**: Actively update T-Pot as described in the [README](https://github.com/telekom-security/tpotce/blob/master/README.md).  
- **Deprecation Notice**: The `24.04` tagged images will no longer be maintained and will be removed by **2025-01-31**.  

### Suricata  
- Capture filters have been updated to exclude broadcast, multicast, NetBIOS, IGMP, and MDNS traffic.  

## Thanks & Credits
A heartfelt thank you to the contributors who made this release possible:
* @elivlo, @mancasa, koalafiedTroll, @trixam, for their backend support!
* @mariocandela for his work and updates on Beelzebub based on our discussions!
* @ryanolee for approaching us and adding valuable features to go-pot based on our discussions! 
* @neon-ninja for the work on #1661!
* @sarkoziadam for the work on #1643!
* @glaslos for the work on #1538!

… and to the entire T-Pot community for opening issues, sharing ideas, and helping improve T-Pot!
