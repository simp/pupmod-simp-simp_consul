# Consul server bootstrap script. This must be run before including
# Consul on your system, see the README for more details.
#
# Generates the following artifacts, and stores them in
# `/etc/simp/bootstrap/consul`:
#
#   1. master_token
#   2. server.dc1.consul.private.pem
#   3. server.dc1.consul.cert.pem
#   4. ca.pem
#   5. key
#
# Instantiates the `simp_consul` class with:
#
#   bootstrap       => true
#   server          => true
#

# Directory generation
#
ensure_resource('file', '/etc/simp', {'ensure' => 'directory'})
file { "/etc/simp/bootstrap/":
  ensure => directory,
}
file { "/etc/simp/bootstrap/consul":
  ensure => directory,
}

# 1. Use `uuidgen` to create the master token
# 2. Use `puppet cert generate` to create the Consul Cert/Key/CA
# 3. Instatiate Consul via `simp_consul`
# 4. Once instantiated, use `consul keygen` to generate a traffic encryption key
# 5. Set the `consul_bootstrapped` fact to true
#
exec { "/usr/bin/uuidgen >/etc/simp/bootstrap/consul/master_token":
  creates => '/etc/simp/bootstrap/consul/master_token',
  require => File["/etc/simp/bootstrap/consul"],
} ->
exec { "/opt/puppetlabs/bin/puppet cert generate server.dc1.consul":
  creates => '/etc/puppetlabs/puppet/ssl/private_keys/server.dc1.consul.pem',
} ->
file { "/etc/simp/bootstrap/consul/server.dc1.consul.private.pem":
  source => '/etc/puppetlabs/puppet/ssl/private_keys/server.dc1.consul.pem',
} ->
file { "/etc/simp/bootstrap/consul/server.dc1.consul.cert.pem":
  source => '/etc/puppetlabs/puppet/ssl/certs/server.dc1.consul.pem',
} ->
file { "/etc/simp/bootstrap/consul/ca.pem":
  source => '/etc/puppetlabs/puppet/ssl/ca/ca_crt.pem',
} -> 
class { "simp_consul":
	bootstrap       => true,
	server          => true,
} ->
exec { "/usr/local/bin/consul keygen >/etc/simp/bootstrap/consul/key":
  path => $::path,
  creates => '/etc/simp/bootstrap/consul/key',
} ->
file { "/opt/puppetlabs/facter/facts.d/consul_bootstrapped.sh":
	mode    => "a+x",
	content => "#!/bin/sh\necho 'consul_bootstrapped=true'",
}
