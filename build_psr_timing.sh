#!/bin/bash

docker buildx build --progress=plain -f psr-timing.dockerfile -t psr-timing:$(date -I) .
