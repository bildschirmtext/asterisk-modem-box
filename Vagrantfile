# -*- mode: ruby -*-
# vi: set ft=ruby :

Vagrant.configure("2") do |config|
  config.vm.box = "generic/debian9"
  config.vm.network "public_network", bridge: [
    'en0: WLAN (AirPort)',
    'en5: USB 10/100/1000 LAN',
  ], mac: '08002769B45A'
  config.vm.provision "shell", path: "provision.sh"
end
