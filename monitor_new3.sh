#!/bin/bash
REPO="whmdg20090421/vault_app"
RUN_ID="24929070418"

echo "开始监视 workflow run: $RUN_ID"

while true; do
    RUN_INFO=$(curl -s -H "Accept: application/vnd.github.v3+json" "https://api.github.com/repos/$REPO/actions/runs/$RUN_ID")
    
    STATUS=$(echo "$RUN_INFO" | grep -m 1 '"status":' | cut -d '"' -f 4)
    CONCLUSION=$(echo "$RUN_INFO" | grep -m 1 '"conclusion":' | cut -d '"' -f 4)

    echo "[$(date '+%Y-%m-%d %H:%M:%S')] 状态: $STATUS"

    if [ "$STATUS" == "completed" ]; then
        if [ "$CONCLUSION" == "success" ]; then
            echo "🎉 Workflow 构建成功完成！"
            exit 0
        else
            echo "❌ Workflow 构建结束，结论: $CONCLUSION"
            exit 1
        fi
    fi

    sleep 30
done
