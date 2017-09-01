def provision_code
  """
    apt-get update && apt-get install -y apt-transport-https docker.io
    curl -s https://packages.cloud.google.com/apt/doc/apt-key.gpg | apt-key add -
    echo 'deb http://apt.kubernetes.io/ kubernetes-xenial main' > /etc/apt/sources.list.d/kubernetes.list
    apt-get update
    apt-get install -y kubelet kubeadm
  """
end

def machine_ip(i)
  "172.17.4.#{100 + i}"
end

def worker_type(i)
  case i
  when 0
    "brain"
  else
    "cell"
  end
end

def token
  "e6ac8e.43f6980db7a3d88d"
end

def network_cidr
  "10.244.0.0/16"
end

Vagrant.configure("2") do |config|
  config.vm.define "master" do |box|
    box.vm.hostname = "master"
    box.vm.box = "ubuntu/xenial64"
    box.vm.network :private_network, ip: machine_ip(0)
    box.vm.provision "shell", inline: provision_code
    box.vm.provision "shell", inline: "kubeadm init --apiserver-advertise-address #{machine_ip 0} --skip-preflight-checks --pod-network-cidr #{network_cidr} --token #{token}"
    box.vm.provision "shell", inline: "cp /etc/kubernetes/admin.conf /vagrant/kubeconfig", privileged: true
    %w(kube-flannel.yml kube-flannel-rbac.yml).each do |manifest|
      box.vm.provision "shell", inline: "kubectl --kubeconfig=/vagrant/kubeconfig apply -f https://raw.githubusercontent.com/coreos/flannel/master/Documentation/#{manifest}"
    end
  end

  3.times do |i|
    config.vm.define "worker#{i + 1}" do |box|
      box.vm.hostname = "worker#{i + 1}"
      box.vm.box = "ubuntu/xenial64"
      box.vm.network :private_network, ip: machine_ip(i + 1)
      box.vm.provision "shell", inline: provision_code
      box.vm.provision "shell", inline: "kubeadm join --token #{token} #{machine_ip 0}:6443"
    end
  end
end
