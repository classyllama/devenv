##
 # Copyright © 2015 by David Alger. All rights reserved
 #
 # Licensed under the Open Software License 3.0 (OSL-3.0)
 # See included LICENSE file for full text of OSL-3.0
 #
 # http://davidalger.com/contact/
 ##

def configure_basebox (node, host: nil, ip: nil, memory: 4096, cpu: 2)
  node.vm.box = 'bento/centos-7.5'

  node.vm.hostname = host
  node.vm.network :private_network, ip: ip, nic_type: "82540EM"
  node.vm.provider "virtualbox" do |vb|
    vb.customize ["modifyvm", :id, "--nictype1", "82540EM"]
  end
  assert_hosts_entry host, ip

  node.vm.graceful_halt_timeout = 120

  node.vm.synced_folder VAGRANT_DIR, '/vagrant'

  # mount persistent shared cache storage on vm and bind sub-caches
  Mount.vmfs('host-cache', SHARED_DIR, SHARED_DIR)
  Mount.bind(SHARED_DIR + '/yum', '/var/cache/yum')
  Mount.bind(SHARED_DIR + '/npm', '/var/cache/npm')

  # setup mount provisioners
  Mount.provision(node)

  # setup the yum cache before vagrant installs ansible in the box (so it can be installed from the cache)
  node.vm.provision :shell do |conf|
    conf.name = "yum-cache"
    conf.inline = 'sed -i \'s/keepcache=0/keepcache = 1\nmetadata_expire = 24h/\' /etc/yum.conf'
  end

  # run the basebox ansible play on the box
  ansible_play(node, 'basebox', {
    host_zoneinfo: File.readlink('/etc/localtime')
  })

  # configure default RAM and number of CPUs allocated to vm
  vm_set_ram(node, memory)
  vm_set_cpu(node, cpu)

  # so we can connect to remote servers from inside the vm
  node.ssh.forward_agent = true
end

def configure_web (node, php_version: 70)
  # verify exports and mount nfs sites location
  Mount.assert_export(MOUNT_PATH + SITES_DIR)
  Mount.nfs('host-www-sites', MOUNT_PATH + SITES_DIR, SITES_MOUNT)

  # bind localhost pub directory
  #Mount.bind(SITES_MOUNT + '/__localhost/pub', '/var/www/html')
  Mount.vmfs('host-html', MOUNT_PATH + SITES_DIR + '/__localhost/pub', '/var/www/html')

  # setup guest provisioners
  Mount.provision(node)
  ansible_play(node, 'web', {
    php_version: php_version,
    shared_ssl_dir: SHARED_DIR + '/ssl'
  })

  # run vhosts.sh on every reload
  node.vm.provision :shell, run: 'always' do |conf|
    conf.name = "vhosts.sh"
    conf.inline = "vhosts.sh --quiet"
  end
end

def configure_percona (node, mysql_version: 56)
  # verify exports and mount nfs mysql data directory
  Mount.assert_export(MOUNT_PATH + '/mysql')
  Mount.nfs('host-mysql-data', MOUNT_PATH + '/mysql/' + node.vm.hostname.sub('dev-', ''), '/var/lib/mysql')

  # setup guest provisioners
  Mount.provision(node)
  ansible_play(node, 'percona', {
    mysql_version: mysql_version
  })

  # start mysqld on every reload (must happen here so mysqld starts after file-system is mounted)
  node.vm.provision :shell, run: 'always' do |conf|
    conf.name = "systemctl start mysqld"
    conf.inline = "systemctl start mysqld"
  end
end

def configure_elasticsearch (node)
  ansible_play(node, 'elasticsearch')
end

def configure_solr (node)
  # bind the solr workspace to the install/download cache location
  Mount.bind(SHARED_DIR + '/solr', '/var/cache/solr')
  Mount.provision(node)

  # provision the box with solr
  ansible_play(node, 'solr')
end
