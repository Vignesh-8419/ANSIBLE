            "repo-config-context"
            "vmware-awx-context"
            "centos-patch-context"
        )
    
    elif [[ "$CLUSTER_NAME" == "rocky-8-servers" ]]; then
    
        TAGS=(
            "patch-el8-context"
            "pxe-rockyos-context"
            "repo-config-context"
            "vmware-awx-context"
            "rocky-patch-context"
        )
    
    elif [[ "$CLUSTER_NAME" == "rocky-9-servers" ]]; then
    
        TAGS=(
            "patch-el9-context"
            "pxe-rocky9-context"
            "repo-config-context"
            "vmware-awx-context"
            "rocky9-patch-context"
        )
    
    else
    
        TAGS=()
    
    fi

    for TAG in "${TAGS[@]}"
    do
        ID=$(get_tag_id "$TAG")

        if [ -n "$ID" ]; then
            TAG_IDS+=("$ID")
            echo "Adding Tag: $TAG"
        fi
    done

    if [ ${#TAG_IDS[@]} -gt 0 ]; then

        JSON_TAGS=$(printf '%s\n' "${TAG_IDS[@]}" | jq -R . | jq -s .)

        curl -sk -X PATCH \
            "$NETBOX_URL/dcim/devices/$DEVICE_ID/" \
            -H "$HDR" \
            -H "Authorization: Token $NETBOX_TOKEN" \
            -d "{\"tags\":$JSON_TAGS}" \
            >/dev/null

        echo "Tags assigned successfully."

    fi

fi

echo "------------------------------------------------"
echo "✅ Finished! $HOSTNAME is updated."
echo "Linked to Cluster ID: $CLUSTER_ID"
echo "------------------------------------------------"

SUCCESS_LIST+="$HOSTNAME"$'\n'

((COUNT++))

done

END_TIME=$(date +%s)
RUNTIME=$((END_TIME-START_TIME))

echo ""
echo "===================================================="

echo -e "${GREEN}SUCCESSFUL HOSTS${NC}"
echo "$SUCCESS_LIST"

echo ""
echo -e "${RED}FAILED HOSTS${NC}"

FAILED_COUNT=$(echo "$FAILED_LIST" | sed '/^$/d' | wc -l)

if [ "$FAILED_COUNT" -eq 0 ]; then
    echo "0"
else
    echo "$FAILED_LIST"
fi

SUCCESS_COUNT=$(echo "$SUCCESS_LIST" | sed '/^$/d' | wc -l)

echo ""
echo "Success Count : $SUCCESS_COUNT"
echo "Failed Count  : $FAILED_COUNT"

echo -e "${CYAN}Execution Time : ${RUNTIME} seconds${NC}"

echo "===================================================="
