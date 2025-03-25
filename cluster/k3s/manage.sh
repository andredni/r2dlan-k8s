#!/bin/sh

K3S_VERSION=$(cat k3s-version.txt)

MASTER_NODE="192.168.15.153"
AGENT_NODES="192.168.15.150 192.168.15.151 192.168.15.152"

TIMEOUT_SECONDS=500
ELAPSED=0

# Check version of master node
MASTER_NODE_VERSION=$(ssh -q pi@${MASTER_NODE} "sudo kubectl version | grep 'Server Version' | awk '{ print \$3 }'")

if [ "${K3S_VERSION}" != "${MASTER_NODE_VERSION}" ]; then

    # Update node - it doesn't matter not to drain the node
    ssh -q pi@${MASTER_NODE} "sudo curl -sfL https://get.k3s.io | INSTALL_K3S_VERSION='${K3S_VERSION}' sh -"

    # Check until version is updated - timeout 5min
    while true; do
        MASTER_NODE_VERSION=$(ssh -q pi@${MASTER_NODE} "sudo kubectl version | grep 'Server Version' | awk '{ print \$3 }'")

        if [ "$MASTER_NODE_VERSION" = "$K3S_VERSION" ]; then
            echo "Successful updated to version: $MASTER_NODE_VERSION"
            break
        fi

        if [ "$ELAPSED" -ge "$TIMEOUT_SECONDS" ]; then
            echo "Timeout after ${TIMEOUT_SECONDS}s: K3s still does not have version $K3S_VERSION (is: $MASTER_NODE_VERSION)"
            exit 1
        fi

        echo "Current version: ${MASTER_NODE_VERSION:-<unkown>} – keep waiting..."
        sleep 2
        ELAPSED=$((ELAPSED + SLEEP_INTERVAL))
    done

    ELAPSED=0
    sleep 10
fi

for AGENT_NODE in ${AGENT_NODES}
do
    AGENT_NODE_VERSION=$(ssh -q pi@${MASTER_NODE} "sudo kubectl  get no -o wide | grep '${AGENT_NODE}' | awk '{ print \$5 }'")

    if [ "${K3S_VERSION}" != "${AGENT_NODE_VERSION}" ]; then

        AGENT_NODE_NAME=$(ssh -q pi@${MASTER_NODE} "sudo kubectl  get no -o wide | grep '${AGENT_NODE}' | awk '{ print \$1 }'")

        # Cordon node
        ssh -q pi@${MASTER_NODE} "sudo kubectl cordon ${AGENT_NODE_NAME}"
        sleep 10

        # Update node - it doesn't matter not to drain the node
        ssh -q pi@${AGENT_NODE} "sudo curl -sfL https://get.k3s.io | INSTALL_K3S_VERSION='${K3S_VERSION}' sh -"

        # Reboot k3s
        ssh -q pi@${AGENT_NODE} "sudo reboot -h now"

        # Check until version is updated - timeout 5min
        while true; do
            AGENT_NODE_VERSION=$(ssh -q pi@${MASTER_NODE} "sudo kubectl  get no -o wide | grep '${AGENT_NODE}' | awk '{ print \$1 }'")

            if [ "$AGENT_NODE_VERSION" = "$K3S_VERSION" ]; then
                echo "Successful updated to version: $AGENT_NODE_VERSION"
                break
            fi

            if [ "$ELAPSED" -ge "$TIMEOUT_SECONDS" ]; then
                echo "Timeout after ${TIMEOUT_SECONDS}s: K3s still does not have version $K3S_VERSION (is: $AGENT_NODE_VERSION)"
                exit 1
            fi

            echo "Current version: ${AGENT_NODE_VERSION:-<unkown>} – keep waiting..."
            sleep 2
            ELAPSED=$((ELAPSED + SLEEP_INTERVAL))
        done

        ELAPSED=0
        sleep 10

        # Uncordon node
        ssh -q pi@${MASTER_NODE} "sudo kubectl uncordon ${AGENT_NODE_NAME}"
        sleep 10

    fi

done