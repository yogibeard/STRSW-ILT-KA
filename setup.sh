#!/bin/bash
# Variables

KEY_TYPE="ecdsa"

KEY_FILE="$HOME/.ssh/id_ecdsa"

PASSPHRASE=""

LINUX_MACHINES=("kubmas1-1" "kubwor1-1" "kubwor1-2" "kubwor1-3")

ONTAP_CLUSTERS=("Cluster1")

VSERVER_NAMES=("Cluster1")

LINUX_USER="root"

LINUX_PASS="Netapp1!"

ONTAP_USER="admin"

ONTAP_PASS="Netapp1!"

LOCAL_SUDO_PASS="Netapp1!"

# Hardcoded VSCode extensions list
VSCODE_EXTENSIONS=(
    "ms-kubernetes-tools.vscode-kubernetes-tools"
    "ms-toolsai.jupyter"
    "ms-python.python"
)

# Registry Mirror String Variables (Assembled dynamically to avoid URL mangling)
SCHEME="https"
DOCKER_DOMAIN="registry-1.docker.io"
GOOGLE_SUB="mirror"
GOOGLE_DOMAIN="gcr.io"


# Update and install packages

echo $LOCAL_SUDO_PASS | sudo -S apt update

echo $LOCAL_SUDO_PASS | sudo -S apt install -y sshpass python3-pip python3.8-venv git



# Generate SSH key

ssh-keygen -t $KEY_TYPE -f $KEY_FILE -N "$PASSPHRASE"



# Function to copy SSH keys to a remote Linux machine

copy_ssh_keys_linux() {

    local user=$1

    local pass=$2

    local host=$3

    sshpass -p "$pass" ssh -o StrictHostKeyChecking=no "$user@$host" "mkdir -p ~/.ssh && chmod 700 ~/.ssh"

    sshpass -p "$pass" scp -o StrictHostKeyChecking=no "$KEY_FILE" "$KEY_FILE.pub" "$user@$host:~/.ssh/"

    sshpass -p "$pass" ssh -o StrictHostKeyChecking=no "$user@$host" "cat ~/.ssh/id_ecdsa.pub >> ~/.ssh/authorized_keys && chmod 600 ~/.ssh/authorized_keys"

}



# Function to create a login and add the public key on a NetApp ONTAP cluster

copy_ssh_key_ontap() {

    local user=$1

    local pass=$2

    local host=$3

    local vserver=$4

    local key_file=$5

    local public_key=$(cat $key_file)

    sshpass -p "$pass" ssh -o StrictHostKeyChecking=no "$user@$host" "security login create -vserver $vserver -user-or-group-name $user -application ssh -authentication-method publickey -role admin ; security login publickey create -vserver $vserver -username $user -publickey \"$public_key\""

}



# Function to install VSCode extensions from an array variable
install_vscode_extensions() {
    for extension in "${VSCODE_EXTENSIONS[@]}"; do
        echo "Installing VSCode extension: $extension"
        code --install-extension "$extension"
    done
}



# Copy SSH keys to Linux machines

for machine in "${LINUX_MACHINES[@]}"; do

    copy_ssh_keys_linux $LINUX_USER $LINUX_PASS $machine

done


# ==============================================================================
# INTEGRATED FIX: Configure Containerd v2 Google Registry Mirror on K8s Nodes
# ==============================================================================
echo "=== Configuring Containerd to use Google Public Mirror on K8s Nodes ==="
SERVER_URL="${SCHEME}://${DOCKER_DOMAIN}"
HOST_URL="${SCHEME}://${GOOGLE_SUB}.${GOOGLE_DOMAIN}"
CONFIG_FILE="/etc/containerd/config.toml"

for machine in "${LINUX_MACHINES[@]}"; do
    echo "Processing registry mirror setup on: $machine"
    
    # Executed via the recently copied root SSH keys
    ssh -o StrictHostKeyChecking=no "root@$machine" "
        # 1. Clear containerd path_config to target v2 registry blocks precisely
        if [ -f \"$CONFIG_FILE\" ]; then
            [ ! -f \"${CONFIG_FILE}.bak\" ] && cp \"$CONFIG_FILE\" \"${CONFIG_FILE}.bak\"
            
            awk '
                /\[plugins\.\"io\.containerd\.cri\.v1\.images\"\.registry\]|\[plugins\.\x27io\.containerd\.cri\.v1\.images\x27\.registry\]/ { 
                    in_registry = 1; 
                    print; 
                    next; 
                }
                in_registry && /config_path[[:space:]]*=/ { 
                    print \"      config_path = \x27/etc/containerd/certs.d\x27\"; 
                    in_registry = 0; 
                    next; 
                }
                { print }
            ' \"$CONFIG_FILE\" > \"${CONFIG_FILE}.tmp\" && mv \"${CONFIG_FILE}.tmp\" \"$CONFIG_FILE\"
        fi

        # 2. Build the un-mangled hosts.toml file structure
        rm -rf /etc/containerd/certs.d/docker.io/*
        mkdir -p /etc/containerd/certs.d/docker.io
        
        echo 'server = \"${SERVER_URL}\"' > /etc/containerd/certs.d/docker.io/hosts.toml
        echo '' >> /etc/containerd/certs.d/docker.io/hosts.toml
        echo '[host.\"${HOST_URL}\"]' >> /etc/containerd/certs.d/docker.io/hosts.toml
        echo '  capabilities = [\"pull\", \"resolve\"]' >> /etc/containerd/certs.d/docker.io/hosts.toml
        
        # 3. Reload engine configurations
        systemctl restart containerd
        echo \"  [OK] Registry updates complete on $machine\"
    "
done
# ==============================================================================


# Copy SSH key to ONTAP clusters

for i in "${!ONTAP_CLUSTERS[@]}"; do

    copy_ssh_key_ontap $ONTAP_USER $ONTAP_PASS "${ONTAP_CLUSTERS[$i]}" "${VSERVER_NAMES[$i]}" "$KEY_FILE.pub"

done



# Install VSCode extensions
install_vscode_extensions


# ==============================================================================
# SECTION: Install kubectl 1.29 via Snap & Sync Kubeconfig
# ==============================================================================
echo "=== Installing kubectl v1.29 on Jumphost ==="
echo $LOCAL_SUDO_PASS | sudo -S snap install kubectl --channel=1.29/stable --classic

echo "=== Copying Cluster Configuration File from kubmas1-1 ==="
mkdir -p "$HOME/.kube"

# Copy the admin config directly from the control node's default location
scp -o StrictHostKeyChecking=no root@kubmas1-1:/etc/kubernetes/admin.conf "$HOME/.kube/config"

# Secure the local configuration file permissions
chmod 600 "$HOME/.kube/config"
echo "[OK] kubectl config is synchronized and secured."
# ==============================================================================


echo "SSH key has been generated and copied to all specified machines and clusters."

echo "VSCode extensions have been installed."
# Create a virtual environment
python3 -m venv myenv

# Activate the virtual environment
source myenv/bin/activate

# Install Jupyter and bash_kernel within the virtual environment
pip install jupyter
pip install bash_kernel
python -m bash_kernel.install
pip install nbconvert

echo "Installation complete. You can now use bash_kernel in Jupyter notebooks within VSCode."


# ==============================================================================
# NEW SECTION: Clone Git Repository and Launch VSCode
# ==============================================================================
echo "=== Cloning STRSW-ILT-KA Git Repository ==="
REPO_DIR="$HOME/Repos/STRSW-ILT-KA"

if [ ! -d "$REPO_DIR" ]; then
    git clone https://github.com/yogibeard/STRSW-ILT-KA.git "$REPO_DIR"
    echo "[OK] Repository cloned into $REPO_DIR"
else
    echo "[INFO] Repository directory already exists at $REPO_DIR. Skipping clone."
fi

echo "=== Launching Visual Studio Code ==="
code "$REPO_DIR"
# ==============================================================================
