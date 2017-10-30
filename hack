#!/usr/bin/env bash

ACTION="create"

POOL=${POOL:-default}
BRAINS=1
CELLS=2
LIBVIRT_DEFAULT_URI="qemu:///system"
DISK_SIZE=10G
CLUSTER_FILE=tmp/cluster.status

IMAGE_NAME=xenial-server-cloudimg-amd64-disk1
IMAGE=$IMAGE_NAME.img
BASE_URL=https://cloud-images.ubuntu.com/xenial/current

while [[ $# > 0 ]] ; do
    case $1 in
        --brains)
            BRAINS="$2"
            shift
            ;;
        -c|--connection)
            export LIBVIRT_DEFAULT_URI="qemu+ssh://$2/system"
            shift
            ;;
        --cells)
            CELLS="$2"
            shift
            ;;
        -d|--destroy)
            ACTION="destroy"
            ;;
    esac
    shift
done

fatal() {
    echo "$1; quitting" >&2
    exit 1
}

info() {
    echo "[I] $1" >&2
}

info "Connection to libvirt: $LIBVIRT_DEFAULT_URI"

SMARTBOX_PATH=$(realpath ${1:-..})
MANIFESTS_PATH=$(realpath $SMARTBOX_PATH/cluster/manifests)

if [ ! -f tmp/$IMAGE ]; then
    wget $BASE_URL/$IMAGE -O tmp/$IMAGE
fi

token() {
    echo "e6ac8e.43f6980db7a3d88d"
}

disk_size() {
    wc -c $1 | cut -d' ' -f1
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
  - docker pull gcr.io/google_containers/kube-proxy-amd64:v1.8.0
  - docker pull gcr.io/google_containers/kube-apiserver-amd64:v1.8.0
  - docker pull gcr.io/google_containers/kube-scheduler-amd64:v1.8.0
  - docker pull gcr.io/google_containers/kube-controller-manager-amd64:v1.8.0
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
password: linux
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
  - kubeadm join --token $(token) master:6443
EOF
    fi

    genisoimage -output $WORKDIR/cloudinit-$1.iso -volid cidata -joliet -rock $WORKDIR/{user,meta}-data &> /dev/null

    virsh vol-create-as --pool $POOL --name cloudinit-$1.iso --capacity $(disk_size "$WORKDIR/cloudinit-$1.iso") --format raw &> /dev/null
    virsh vol-upload --pool $POOL --vol cloudinit-$1.iso --file $WORKDIR/cloudinit-$1.iso &> /dev/null

    rm -rf $WORKDIR
}

build_network() {
    info "Setting network up"
    virsh net-destroy smartbox &> /dev/null
    virsh net-undefine smartbox &> /dev/null
    network_definition=$(mktemp)
    cat > $network_definition <<'EOF'
      <network>
        <name>smartbox</name>
        <bridge name="virbr10"/>
        <forward/>
        <ip address="192.168.200.1" netmask="255.255.255.0">
          <dhcp>
            <range start="192.168.200.2" end="192.168.200.254"/>
          </dhcp>
        </ip>
        <domain name="smartbox.io" localOnly="yes"/>
      </network>
EOF
    virsh net-define $network_definition &> /dev/null
    virsh net-start smartbox &> /dev/null
    virsh net-autostart smartbox &> /dev/null
    info "Network configured"
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
                     --network network=smartbox \
                     --graphics none \
                     --disk vol=$POOL/$IMAGE_NAME-with-deps.img,format=qcow2,bus=virtio,cache=writeback \
                     --disk vol=$POOL/cloudinit-bootstrap.iso,bus=virtio &> /dev/null
        virsh undefine image-bootstrap &> /dev/null
    fi
}

build_volumes() {
    info "Building volumes"
    if ! virsh vol-list --pool $POOL | grep $IMAGE &> /dev/null; then
        info "Uploading $IMAGE"
        virsh vol-create-as --pool $POOL --name $IMAGE --capacity $(disk_size "tmp/$IMAGE") --format qcow2 --prealloc-metadata &> /dev/null
        virsh vol-upload --pool $POOL --vol $IMAGE --file tmp/$IMAGE &> /dev/null
    fi
    build_volume_base
    virsh vol-create-as --pool $POOL --name $1.img --capacity $DISK_SIZE --format qcow2 --backing-vol $IMAGE_NAME-with-deps.img --backing-vol-format qcow2 &> /dev/null
    info "Volumes built"
}

build_vm() {
    machine_id="$1-$(uuidgen -r)"
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
                 --network network=smartbox \
                 --graphics none \
                 --disk vol=$POOL/$machine_id.img,format=qcow2,bus=virtio,cache=writeback \
                 --disk vol=$POOL/cloudinit-$machine_id.iso,bus=virtio &> /dev/null &
    info "Machine $machine_id created"
    info "Waiting for DHCP lease for $machine_id..."
    while ! virsh -q domifaddr $machine_id | grep ipv4; do sleep 0.1; done &> /dev/null
    machine_ip=$(virsh domifaddr $machine_id | grep ipv4 | awk '{print $4}' | cut -d/ -f1)
    info "DHCP lease obtained for $machine_id: $machine_ip"
    echo "$machine_id $machine_ip"
}

do_create() {
    [ ! -f $CLUSTER_FILE ] || fatal "$CLUSTER_FILE exists, destroy first"

    build_network

    echo $(build_vm "master") > $CLUSTER_FILE

    for i in $(seq 1 $BRAINS); do
        echo $(build_vm "brain") >> $CLUSTER_FILE
    done

    for i in $(seq 1 $CELLS); do
        echo $(build_vm "cell") >> $CLUSTER_FILE
    done
}

do_destroy() {
    [ -f $CLUSTER_FILE ] || fatal "$CLUSTER_FILE does not exist, create first"

    for machine_id in $(cat $CLUSTER_FILE | cut -d" " -f1); do
        virsh destroy $machine_id &> /dev/null
        virsh undefine $machine_id --remove-all-storage &> /dev/null
        info "Machine $machine_id destroyed"
    done

    rm $CLUSTER_FILE
}

case $ACTION in
    "create")
        do_create
        ;;
    "destroy")
        do_destroy
        ;;
    *)
        fatal "unknown action: $ACTION"
        ;;
esac
