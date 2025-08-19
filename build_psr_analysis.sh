#!/bin/bash

#docker buildx build --no-cache --progress=plain -f psr-analysis.dockerfile -t psr-analysis:$(date -I) .
docker buildx build --progress=plain -f psr-analysis.dockerfile -t psr-analysis:$(date -I) .

docker image tag psr-analysis:$(date -I) cirapulsarsandtransients/psr-analysis:$(date -I)
docker image tag cirapulsarsandtransients/psr-analysis:$(date -I) cirapulsarsandtransients/psr-analysis:latest
