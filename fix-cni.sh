#!/bin/bash

# Define your nodes
CONTROL_NODE="root@kubmas1-1"
WORKER_NODES=("root@kubwor1-1" "root@kubwor1-2" "root@kubwor1-3")
ALL_NODES=("$CONTROL_NODE" "${WORKER_NODES[@]}")

echo "=== Step 1: Deleting old CNI resources from control node ==="
ssh "$CONTROL_NODE" "
  kubectl delete -f  https://github.com/weaveworks/weave/releases/latest/download/weave-daemonset-k8s.yaml --ignore-not-found
  kubectl delete -f https://raw.githubusercontent.com/flannel-io/flannel/master/Documentation/kube-flannel.yml  --ignore-not-found
"

echo "=== Step 2: Cleaning up network directories and restarting services on ALL nodes ==="
for node in "${ALL_NODES[@]}"; do
  echo "Processing node: $node"
  ssh "$node" "
    rm -rf /etc/cni/net.d/*
    rm -rf /var/lib/cni/*
    rm -rf /run/flannel
    systemctl restart containerd
    systemctl restart kubelet
  "
done

echo "=== Step 3: Downloading, modifying, and applying Calico on control node ==="
ssh "$CONTROL_NODE" "
  curl -sO  https://raw.githubusercontent.com/projectcalico/calico/v3.27.3/manifests/calico.yaml
  sed -i 's#docker.io/calico/#quay.io/calico/#g' calico.yaml
  kubectl apply -f calico.yaml
"

echo "=== Step 4: Restarting Calico pods to ensure fresh start ==="
ssh "$CONTROL_NODE" "
  kubectl delete pod -n kube-system -l k8s-app=calico-node --ignore-not-found
  kubectl delete pod -n kube-system -l k8s-app=calico-kube-controllers --ignore-not-found
"

echo "=== Script completed successfully ==="
