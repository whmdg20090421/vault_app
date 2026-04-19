#!/bin/bash
TOKEN="ghu_knFivR6WhwGSC03KgGQ6xUHe7HOasD0hzX6S"
REPO="whmdg20090421/vault_app"

while true; do
  RUN_INFO=$(curl -s -H "Authorization: Bearer $TOKEN" https://api.github.com/repos/$REPO/actions/runs?per_page=1)
  STATUS=$(echo "$RUN_INFO" | grep -m 1 '"status"' | cut -d '"' -f 4)
  CONCLUSION=$(echo "$RUN_INFO" | grep -m 1 '"conclusion"' | cut -d '"' -f 4)
  HTML="<html><body><h1>CI Status: $STATUS</h1><h2>Conclusion: $CONCLUSION</h2><p>$(date)</p></body></html>"
  echo "$HTML" > /workspace/ci_status.html
  if [ "$STATUS" == "completed" ]; then
    break
  fi
  sleep 5
done
