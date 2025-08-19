#!/bin/bash

docker buildx build --no-cache --progress=plain -f psr-search.dockerfile -t psr-search:$(date -I) .
#docker buildx build --progress=plain -f psr-search.dockerfile -t psr-search:$(date -I) .

docker image tag psr-search:$(date -I) cirapulsarsandtransients/psr-search:$(date -I)
docker image tag cirapulsarsandtransients/psr-search:$(date -I) cirapulsarsandtransients/psr-search:latest
