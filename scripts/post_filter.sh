#!/usr/bin/env bash
# if multi-map, append map name after timestamp.
multimap=$([ -n "${MULTI_MAP}" ] && echo "[${SERVER_MAP}] " || echo "")
sed -u -re "s/^([^|]+)\|/\1 ${multimap}/"
