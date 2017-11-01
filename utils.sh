CLUSTER=

fatal() {
    echo "$1; quitting" >&2
    exit 1
}

info() {
    echo "[I] $1" >&2
}

clusters() {
    find tmp/clusters -type f | grep -v gitkeep | cut -d/ -f3
}

cluster() {
    if [ ! -z $CLUSTER ]; then
        echo $CLUSTER
    else
        if [ $(clusters | wc -l) -eq "1" ]; then
            echo $(clusters | head -n1)
        else
            fatal "no CLUSTER defined"
        fi
    fi
}

cluster_file() {
    echo "tmp/clusters/$(cluster)"
}

host() {
    grep host $(cluster_file) | cut -d" " -f2
}

network() {
    echo "smartbox-io-$(cluster)"
}

master() {
    masters | sort -R | head -n1
}

master_ip() {
    grep $(master) $(cluster_file) | cut -d" " -f2
}

masters() {
    machines | grep master
}

machines() {
    grep -v host $(cluster_file) | cut -d" " -f1
}
