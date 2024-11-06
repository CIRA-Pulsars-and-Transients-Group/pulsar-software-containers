#!/bin/bash

docker buildx build --progress=plain -f psr-search.dockerfile -t psr-search:$(date -I) .
