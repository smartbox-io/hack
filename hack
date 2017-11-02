#!/usr/bin/env bash

. utils.sh

ACTION="create"

POOL=${POOL:-"default"}
BRAINS="1"
CELLS="2"
HOST="localhost"
LIBVIRT_DEFAULT_URI="qemu:///system"
DISK_SIZE="10G"

IMAGE_NAME="xenial-server-cloudimg-amd64-disk1"
IMAGE="$IMAGE_NAME.img"
BASE_URL="https://cloud-images.ubuntu.com/xenial/current"

while [[ $# > 0 ]] ; do
    case $1 in
        --brains)
            BRAINS="$2"
            shift
            ;;
        --cells)
            CELLS="$2"
            shift
            ;;
        -c|--cluster-name)
            export CLUSTER="$2"
            shift
            ;;
        -d|--destroy)
            ACTION="destroy"
            ;;
        --destroy-all)
            ACTION="destroy_all"
            ;;
        -h|--host)
            HOST="$2"
            export LIBVIRT_DEFAULT_URI="qemu+ssh://$2/system"
            shift
            ;;
        -w|--wait)
            ACTION="wait"
            ;;
    esac
    shift
done

info "Connection to libvirt: $LIBVIRT_DEFAULT_URI"

if [ ! -f tmp/$IMAGE ]; then
    wget $BASE_URL/$IMAGE -O tmp/$IMAGE
fi

token() {
    echo "e6ac8e.43f6980db7a3d88d"
}

disk_size() {
    wc -c $1 | cut -d" " -f1
}

build_cloudinit_bootstrap() {
    WORKDIR=$(mktemp -d cloudinit-bootstrap-XXXXXXXX)

    cat > $WORKDIR/meta-data <<EOF
instance-id: iid-cloudinit-bootstrap
EOF

    cat > $WORKDIR/user-data <<EOF
#cloud-config
ssh_authorized_keys:
  - ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQDYhRewFL7luLkp0L8PD+9nY0NS6mb5HeAf623XKg6Jjyoipvaqgjh4Km5sod0RGxDRFne7uazB0CAt5srovU0nnVmoTBCJYs84/0dHj6X+66GP1qMLCBs/n6cnUBraDi82bBrknXAqEHs4ujHpslmJEaoL4OOJW3Q42e1lWTpLyjqiV2m1YVpTmrHxvDsSfPto+gM4ssKC4YZW4EdUp/BK79GDdj3KiSTqhclvP5m1MLzQ3/Xy3kNr+HfKx8NdHZAF/+qeOcQHwX2OH88mrZvSJppcmR/Ru/yTV13gUs8SRfHYSFgm/pF7c+UcWQSfHjUtH6OxFUipHznBZs03qFtl insecure@key
runcmd:
  - apt-get update && apt-get install -y apt-transport-https docker.io
  - curl -s https://packages.cloud.google.com/apt/doc/apt-key.gpg | apt-key add -
  - echo 'deb http://apt.kubernetes.io/ kubernetes-xenial main' > /etc/apt/sources.list.d/kubernetes.list
  - apt-get update
  - apt-get install -y kubelet kubeadm
  - docker pull quay.io/coreos/flannel:v0.8.0-amd64
  - docker pull gcr.io/google_containers/etcd-amd64:3.0.17
  - docker pull gcr.io/google_containers/pause-amd64:3.0
  - docker pull gcr.io/google_containers/kube-proxy-amd64:v1.8.2
  - docker pull gcr.io/google_containers/kube-apiserver-amd64:v1.8.2
  - docker pull gcr.io/google_containers/kube-scheduler-amd64:v1.8.2
  - docker pull gcr.io/google_containers/kube-controller-manager-amd64:v1.8.2
  - shutdown -h now
EOF

    genisoimage -output $WORKDIR/cloudinit-bootstrap.iso -volid cidata -joliet -rock $WORKDIR/{user,meta}-data &> /dev/null

    virsh vol-create-as --pool $POOL --name cloudinit-bootstrap.iso --capacity $(disk_size "$WORKDIR/cloudinit-bootstrap.iso") --format raw &> /dev/null
    virsh vol-upload --pool $POOL --vol cloudinit-bootstrap.iso --file $WORKDIR/cloudinit-bootstrap.iso &> /dev/null

    rm -rf $WORKDIR
}

build_cloudinit() {
    WORKDIR=$(mktemp -d cloudinit-$1-XXXXXXXX)

    cat > $WORKDIR/meta-data <<EOF
instance-id: iid-$1
EOF

    cat > $WORKDIR/user-data <<EOF
#cloud-config
hostname: $1
fqdn: $1.smartbox.io
ssh_authorized_keys:
  - ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQDYhRewFL7luLkp0L8PD+9nY0NS6mb5HeAf623XKg6Jjyoipvaqgjh4Km5sod0RGxDRFne7uazB0CAt5srovU0nnVmoTBCJYs84/0dHj6X+66GP1qMLCBs/n6cnUBraDi82bBrknXAqEHs4ujHpslmJEaoL4OOJW3Q42e1lWTpLyjqiV2m1YVpTmrHxvDsSfPto+gM4ssKC4YZW4EdUp/BK79GDdj3KiSTqhclvP5m1MLzQ3/Xy3kNr+HfKx8NdHZAF/+qeOcQHwX2OH88mrZvSJppcmR/Ru/yTV13gUs8SRfHYSFgm/pF7c+UcWQSfHjUtH6OxFUipHznBZs03qFtl insecure@key
runcmd:
  - systemctl restart networking
EOF

    if [[ "$1" =~ ^master ]]; then
        cat >> $WORKDIR/user-data <<EOF
  - kubeadm init --apiserver-advertise-address \$(dig $1 +short) --skip-preflight-checks --pod-network-cidr 10.244.0.0/16 --token $(token)
  - export KUBECONFIG=/etc/kubernetes/admin.conf
  - kubectl apply -f https://raw.githubusercontent.com/coreos/flannel/v0.8.0/Documentation/kube-flannel.yml
  - kubectl apply -f https://raw.githubusercontent.com/coreos/flannel/v0.8.0/Documentation/kube-flannel-rbac.yml
EOF
    else
        cat >> $WORKDIR/user-data <<EOF
  - kubeadm join --token $(token) $(master):6443
EOF
    fi

    genisoimage -output $WORKDIR/cloudinit-$1.iso -volid cidata -joliet -rock $WORKDIR/{user,meta}-data &> /dev/null

    virsh vol-create-as --pool $POOL --name cloudinit-$1.iso --capacity $(disk_size "$WORKDIR/cloudinit-$1.iso") --format raw &> /dev/null
    virsh vol-upload --pool $POOL --vol cloudinit-$1.iso --file $WORKDIR/cloudinit-$1.iso &> /dev/null

    rm -rf $WORKDIR
}

build_network() {
    network_id="smartbox-io-$CLUSTER"
    info "Creating network $network_id"
    while true; do
        network_count=$(virsh net-list | grep smartbox-io | wc -l)
        network_definition=$(mktemp)
        cat > $network_definition <<EOF
          <network>
          <name>$network_id</name>
          <bridge name="virbr$(expr 10 + $network_count)"/>
          <forward/>
          <ip address="192.168.$(expr 200 + $network_count).1" netmask="255.255.255.0">
            <dhcp>
              <range start="192.168.$(expr 200 + $network_count).2" end="192.168.$(expr 200 + $network_count).254"/>
            </dhcp>
          </ip>
          <domain name="smartbox.io" localOnly="yes"/>
        </network>
EOF
        if virsh net-define $network_definition &> /dev/null; then
            break
        fi
    done
    virsh net-start $network_id &> /dev/null
    virsh net-autostart $network_id &> /dev/null
    info "Network $network_id configured"
}

build_volume_base() {
    if ! virsh vol-list --pool $POOL | grep $IMAGE_NAME-with-deps.img &> /dev/null; then
        info "Building base image with dependencies included"
        build_cloudinit_bootstrap
        virsh vol-create-as --pool $POOL --name $IMAGE_NAME-with-deps.img --capacity $DISK_SIZE --format qcow2 --backing-vol $IMAGE --backing-vol-format qcow2 &> /dev/null
        virt-install --name image-bootstrap \
                     --vcpus 2 \
                     --cpu host \
                     --ram 2048 \
                     --autostart \
                     --memballoon virtio \
                     --boot hd \
                     --os-type linux \
                     --os-variant generic \
                     --network network=$(network) \
                     --graphics none \
                     --disk vol=$POOL/$IMAGE_NAME-with-deps.img,format=qcow2,bus=virtio,cache=writeback \
                     --disk vol=$POOL/cloudinit-bootstrap.iso,bus=virtio &> /dev/null
        virsh undefine image-bootstrap &> /dev/null
    fi
}

build_volumes() {
    info "Building volumes for $1"
    if ! virsh vol-list --pool $POOL | grep $IMAGE &> /dev/null; then
        info "Uploading $IMAGE"
        virsh vol-create-as --pool $POOL --name $IMAGE --capacity $(disk_size "tmp/$IMAGE") --format qcow2 --prealloc-metadata &> /dev/null
        virsh vol-upload --pool $POOL --vol $IMAGE --file tmp/$IMAGE &> /dev/null
    fi
    build_volume_base
    virsh vol-create-as --pool $POOL --name $1.img --capacity $DISK_SIZE --format qcow2 --backing-vol $IMAGE_NAME-with-deps.img --backing-vol-format qcow2 &> /dev/null
    info "Volumes built for $1"
}

build_vm() {
    machine_id="$1-$CLUSTER"
    info "Building machine $machine_id"
    build_cloudinit $machine_id
    build_volumes $machine_id
    virt-install --name $machine_id \
                 --vcpus 2 \
                 --cpu host \
                 --ram 2048 \
                 --autostart \
                 --memballoon virtio \
                 --boot hd \
                 --os-type linux \
                 --os-variant generic \
                 --network network=$(network) \
                 --graphics none \
                 --disk vol=$POOL/$machine_id.img,format=qcow2,bus=virtio,cache=writeback \
                 --disk vol=$POOL/cloudinit-$machine_id.iso,bus=virtio &> /dev/null &
    info "Machine $machine_id created"
    echo "$machine_id waiting-for-dhcp-lease"
}

wait_for_dhcp_leases() {
    info "Waiting for DHCP leases..."
    while grep waiting-for-dhcp-lease $(cluster_file) &> /dev/null; do
        for machine_id in $(machines); do
            if ! grep "$machine_id waiting-for-dhcp-lease" $(cluster_file) &> /dev/null; then
                continue
            fi
            if virsh net-dhcp-leases $(network) | grep $machine_id | grep ipv4 &> /dev/null; then
                machine_ip=$(virsh net-dhcp-leases $(network) | grep $machine_id | grep ipv4 | awk '{print $5}' | cut -d/ -f1)
                sed -i "s/$machine_id waiting-for-dhcp-lease/$machine_id $machine_ip/g" $(cluster_file)
                info "DHCP lease obtained for $machine_id: $machine_ip"
            fi
        done
    done
}

do_create() {
    info "Creating $CLUSTER cluster"

    [ ! -f $(cluster_file) ] || fatal "$(cluster_file) exists, destroy first"

    echo "host $HOST" > $(cluster_file)

    build_network

    build_vm "master" >> $(cluster_file)

    for i in $(seq 1 $BRAINS); do
        build_vm "brain-$i" >> $(cluster_file)
    done

    for i in $(seq 1 $CELLS); do
        build_vm "cell-$i" >> $(cluster_file)
    done

    wait_for_dhcp_leases

    info "Cluster $CLUSTER created"
}

do_destroy() {
    info "Destroying $CLUSTER cluster"

    [ -f $(cluster_file) ] || fatal "$(cluster_file) does not exist, create first"

    virsh net-destroy $(network) &> /dev/null
    virsh net-undefine $(network) &> /dev/null
    info "Network $(network) destroyed"

    for machine_id in $(machines); do
        virsh destroy $machine_id &> /dev/null
        virsh undefine $machine_id --remove-all-storage &> /dev/null
        info "Machine $machine_id destroyed"
    done

    rm $(cluster_file)

    info "Cluster $CLUSTER destroyed"
}

do_destroy_all () {
    for cluster in $(clusters); do
        CLUSTER=$cluster
        do_destroy
    done
}

do_wait() {
    info "Waiting for all nodes to be ready..."
    ARGS="get nodes"
    while [ $(./kubectl get nodes | grep -v NotReady | grep Ready | wc -l) -ne $(machines | wc -l) ]; do
        sleep 1
    done
    info "All nodes ready ($(machines | wc -l))"
}

case $ACTION in
    "create")
        CLUSTER=$(uuidgen -r | cut -d- -f1)
        do_create
        ;;
    "destroy")
        do_destroy
        ;;
    "destroy_all")
        do_destroy_all
        ;;
   "wait")
        do_wait
        ;;
    *)
        fatal "unknown action: $ACTION"
        ;;
esac

info "All set!"
