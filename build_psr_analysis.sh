#!/bin/bash

docker buildx build --progress=plain -f psr-analysis.dockerfile -t psr-analysis:$(date -I) .
