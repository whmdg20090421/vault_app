#!/bin/bash
TOKEN="ghu_gfyq9RCLZzZKM6E1rPrbAE34GPr1iy0pO5qq"
RUN_ID="24540545010"
URL="https://api.github.com/repos/whmdg20090421/vault_app/actions/runs/$RUN_ID"

while true; do
  STATUS=$(curl -s -H "Authorization: token $TOKEN" -H "Accept: application/vnd.github.v3+json" $URL | jq -r '.status')
  CONCLUSION=$(curl -s -H "Authorization: token $TOKEN" -H "Accept: application/vnd.github.v3+json" $URL | jq -r '.conclusion')
  
  if [ "$STATUS" == "completed" ]; then
    echo "Run completed with conclusion: $CONCLUSION"
    break
  fi
  echo "Current status: $STATUS. Waiting 15 seconds..."
  sleep 15
done
