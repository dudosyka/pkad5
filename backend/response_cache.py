from collections import OrderedDict
from functools import wraps
import hashlib
import json
from pathlib import Path
from threading import Lock

from fastapi.encoders import jsonable_encoder
from fastapi.responses import JSONResponse, Response

from db import database


BUILD = hashlib.sha256(b"".join(path.read_bytes() for path in sorted(Path(__file__).parent.glob("*.py")))).hexdigest()
responses = OrderedDict()
cache_lock = Lock()


def cached(*, content=False):
    def decorate(endpoint):
        @wraps(endpoint)
        def respond(*args, **kwargs):
            request = kwargs["request"]


            with database() as connection:
                latest = connection.execute("""
                    SELECT run_id, metrics FROM core.pipeline_runs
                    WHERE finished_at IS NOT NULL ORDER BY run_id DESC LIMIT 1
                """).fetchone()
                if latest is None:
                    return endpoint(*args, **kwargs)
                version = latest["metrics"] if content else latest["run_id"]
                key = json.dumps([BUILD, request.url.path,
                                  sorted(request.query_params.multi_items(), key=lambda item: item[0]),
                                  version], sort_keys=True)
                etag = '"' + hashlib.sha256(key.encode()).hexdigest() + '"'
                headers = {"ETag": etag, "Cache-Control": "private, no-cache"}
                validators = request.headers.get("if-none-match", "").split(",")
                if any(value.strip().removeprefix("W/") in (etag, "*") for value in validators):
                    return Response(status_code=304, headers=headers)
                with cache_lock:
                    body = responses.get(etag)
                    hit = body is not None
                    if body is None:
                        body = JSONResponse(jsonable_encoder(endpoint(*args, **kwargs))).body
                        responses[etag] = body
                        if len(responses) > 128:
                            responses.popitem(last=False)
                    responses.move_to_end(etag)
                return Response(body, media_type="application/json",
                                headers={**headers, "X-Cache": "HIT" if hit else "MISS"})
        return respond
    return decorate
