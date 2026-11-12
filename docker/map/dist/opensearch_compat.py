"""OpenSearch client for the T-Pot Attack Map data server.

The data server (telekom-security/t-pot-attack-map) is written against the
Elasticsearch Python client API. This module implements the small subset of that
API it uses on top of opensearch-py; the Dockerfile patches the data server to
import this class instead:

  OpenSearchClient(url).info()
  OpenSearchClient(url).search(index=..., query=..., size=..., sort=..., pit=..., ...)
  OpenSearchClient(url).open_point_in_time(index=..., keep_alive=...)  -> {"id": ...}
  OpenSearchClient(url).close_point_in_time(id=...)
"""
from opensearchpy import OpenSearch
from opensearchpy.exceptions import RequestError

# Keyword arguments of search() that belong into the request body.
_BODY_KEYS = ("query", "aggs", "aggregations", "size", "from_", "sort", "pit",
              "search_after", "track_total_hits", "_source", "fields")


class OpenSearchClient:
    def __init__(self, hosts, **kwargs):
        if isinstance(hosts, str):
            hosts = [hosts]
        self._client = OpenSearch(hosts=hosts, **kwargs)

    def info(self, **kwargs):
        return self._client.info(**kwargs)

    def search(self, index=None, **kwargs):
        body = {}
        for key in _BODY_KEYS:
            if key in kwargs:
                value = kwargs.pop(key)
                body["from" if key == "from_" else key] = value
        # Searches inside a point in time must not name an index.
        if "pit" in body:
            index = None
            if body["pit"].get("id") is None:
                # see open_point_in_time(): no logstash-* index exists yet
                return {"hits": {"total": {"value": 0, "relation": "eq"}, "hits": []}}
        return self._client.search(index=index, body=body, **kwargs)

    def open_point_in_time(self, index, keep_alive, **kwargs):
        try:
            res = self._client.create_pit(index=index, params={"keep_alive": keep_alive})
        except RequestError as e:
            # OpenSearch refuses a point in time on a wildcard that matches no index
            # yet ("invalid id: [null]"), i.e. on a fresh installation before the
            # first event. Treat it as an empty result.
            if "invalid id" in str(e):
                return {"id": None}
            raise
        return {"id": res["pit_id"]}

    def close_point_in_time(self, id, **kwargs):
        if id is None:
            return {"pits": []}
        return self._client.delete_pit(body={"pit_id": [id]})

    def close(self):
        self._client.close()
