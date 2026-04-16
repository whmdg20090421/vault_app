#!/bin/bash
RUN_ID=24515271510
TOKEN="ghu_gfyq9RCLZzZKM6E1rPrbAE34GPr1iy0pO5qq"
REPO="whmdg20090421/vault_app"

while true; do
  STATUS=$(curl -s -H "Authorization: token $TOKEN" "https://api.github.com/repos/$REPO/actions/runs/$RUN_ID" | grep '"status":' | head -n 1 | awk -F'"' '{print $4}')
  if [ "$STATUS" == "completed" ]; then
    CONCLUSION=$(curl -s -H "Authorization: token $TOKEN" "https://api.github.com/repos/$REPO/actions/runs/$RUN_ID" | grep '"conclusion":' | head -n 1 | awk -F'"' '{print $4}')
    echo "Build completed with conclusion: $CONCLUSION"
    break
  fi
  echo "Build status: $STATUS, waiting 10 seconds..."
  sleep 10
done
