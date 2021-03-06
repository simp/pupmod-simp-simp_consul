# == Class simp_consul
#
# This is a profile class which wraps solarkennedy/consul.
#
# @param bootstrap
#   Boolean.  This should only be utilized by bootstrap/consul.pp. If you need
#   to re-bootstrap, re-apply consul.pp
#   If true:
#     - Don't create/ensure the libkv and agent tokens
#   If false:
#     - If `$manage_pki` is true, ensure certificates, and create the cert_hash
#
#   Defaults to false
#
# @param firewall
#   Boolean.  If true, open the following ports via iptables:
#     tcp: [8300,8301,8302,8500,8600]
#     udp: [8301,8302,8600]
#   Controlled by simp_options::firewall.
#
#   Defaults to false
#
# @param server
#   Boolean.  Used in this class as control logic, and passed as `server` to
#   the `::consul` class.  A value of false will configure the agent to be a
#   client.
#
#   Defaults to false
#
# @param version
#   Passed as `version` to the `::consul` class.
#
#   Defaults to '0.8.5'
#
# @param manage_pki
#   Boolean.  Not effective during bootstrap ($bootstrap == true).
#   If true:
#     - Certs will be copied to `/etc/simp/consul`, and the
#       following cert_hash will be passed to the `::conul` class:
#          "cert_file"              => '/etc/simp/consul/cert.pem',
#          "ca_file"                => '/etc/simp/consul/ca.pem',
#          "key_file"               => '/etc/simp/consul/key.pem',
#          "verify_outgoing"        => true,
#          "verify_incoming"        => true,
#          "verify_server_hostname" => true,
#     - By default, certs will be copied from /etc/simp/bootstrap/consul.  You
#       can specify alternate certificate paths using the params below.
#
#   Defaults to true
#
# @param cert_file
#   Full path to cert_file, to be copied to `/etc/simp/consul`
#
#   Defaults to undef
#
# @param key_file
#   Full path to key_file, to be copied to `/etc/simp/consul`
#
#   Defaults to undef
#
# @param ca_file
#   Full path to ca_file, to be copied to `/etc/simp/consul`
#
#   Defaults to undef
#
# @param serverhost
#   Passed as `retry_join` to `::consul`
#
#   Defaults to undef
#
# @param http_listen   
#   Passed as `http` to `::consul`
#
#   Defaults to '127.0.0.1'
#
# @param https_listen
#   Passed as `https` to `::consul`
#
#   Defaults to undef
#
# @param advertise
#   Passed as `advertise_addr` to `::consul`
#
#   Defaults to undef
#
# @param datacenter
#   Passed as `datacenter` to `::consul`
#
#   Defaults to undef
#
# @param puppet_cert_path
#   Path to base dir of puppet certs
#
#   Defaults specified in data/
#
# @param config_hash
#   Hash of configuration parameters for `::consul`, merged with the hash
#   generated by this profile.
#
#   Defaults to undef
#
# @param agent_token
#   Path to agent token.  If undef and $server == true, master_token is passed
#   as the acl_token to `::consul`.  If undef and $client == true, look for an
#   agent_token in libkv; if one does not exist, create one and store it in
#   libkv, then pass it as the acl_token to `::consul`.
#
#   Defaults to undef
#
class simp_consul(
  $bootstrap         = false,
  $firewall          = simplib::lookup('simp_options::firewall', { 'default_value' => false }),
  $server            = false,
  $version           = '0.8.5',
  $manage_pki        = true,
  $cert_file         = undef,
  $key_file          = undef,
  $ca_file           = undef,
  $serverhost        = undef,
  $http_listen       = '127.0.0.1',
  $https_listen      = '0.0.0.0',
  $advertise         = undef,
  $datacenter        = undef,
  # Defined in data/
  $puppet_cert_path,
  $config_hash       = undef,
  $agent_token       = undef,
) {

  package { "unzip": }

  if ($firewall) {
    $tcp_ports = [
      8300,
      8301,
      8302,
      8500,
      8600,
    ]
    $udp_ports = [
      8301,
      8302,
      8600,
    ]
    $tcp_ports.each |$port| {
      iptables::listen::tcp_stateful { "simp_consul - tcp - ${port}":
        dports => $port,
      }
    }
    $udp_ports.each |$port|{
      iptables::listen::udp { "simp_consul - udp - ${port}":
        dports => $port,
      }
    }
  }

  file { "/usr/bin/consul-acl":
    ensure => 'file',
    mode   => "a=rx,u+w",
    source => "puppet:///modules/simp_consul/consul-acl"
  }
  file { "/usr/bin/consul-create-acl":
    ensure => 'file',
    mode   => "a=rx,u+w",
    source => "puppet:///modules/simp_consul/consul-create-acl"
  }

  #
  # Generates: bootstrap_hash
  # Actions: agent and libkv token creation
  #
  # First pass during bootstrap, skip token creation
  if ($bootstrap == true) {
    $_bootstrap_hash = { "bootstrap_expect" => 1 }
  }
  # Once bootstrapped, create libkv_token and agent_token, via `consul-create-acl`
  else {
    # consul_bootstrapped fact forced true in bootstrap.pp
    if ($facts["consul_bootstrapped"] == "true") {
      $_bootstrap_hash = { "bootstrap_expect" => 1 }
      # Create real token
      exec { "/usr/bin/consul-create-acl -t libkv /etc/simp/bootstrap/consul/master_token /etc/simp/bootstrap/consul/libkv_token":
        creates => "/etc/simp/bootstrap/consul/libkv_token",
        require => [
          Service['consul'],
          File["/usr/bin/consul-acl"],
        ],
      }
      exec { "/usr/bin/consul-create-acl -t agent_token /etc/simp/bootstrap/consul/master_token /etc/simp/bootstrap/consul/agent_token":
        creates => "/etc/simp/bootstrap/consul/agent_token",
        require => [
          Service['consul'],
          File["/usr/bin/consul-acl"],
        ],
      }
    }
    else {
      $_bootstrap_hash = {}
    }
  }

  #
  # Generates: token_hash
  #
  if ($agent_token == undef) {
    $master_token_path = '/etc/simp/bootstrap/consul/master_token'
    $master_token = file($master_token_path, "/dev/null")

    # If we're a server and a master_token exists, set token_hash = master_token
    if ($server == true) {
      if ($master_token != undef) {
        $_token_hash = {
        "acl_master_token" => $master_token.chomp,
        "acl_token"        => $master_token.chomp,
        }
      }
      else {
        $_token_hash = {}
      }
    }
    # If we're a client, attempt to get a token from libkv.  If that fails,
    # attempt to generate one via `consul-acl`, and put it in libkv.
    else {
      $_agent_token = libkv::get({"softfail" => true, "key" => "/simp/libkv/consul/acls/${::clientcert}-${::hostname}"})
      if ($_agent_token != undef) {
        $_token_hash = {
        "acl_token"        => $_agent_token.chomp,
        }
      }
      else {
        $try_agent_token = generate("/usr/bin/consul-acl", "-t", "agent",  "gen", "${::clientcert}", "${::hostname}").chomp
        if ($try_agent_token != "") {
          $result = libkv::put({"softfail" => true, "key" => "/simp/libkv/consul/acls/${::clientcert}-${::hostname}", "value" => $try_agent_token.chomp})
          $_token_hash = {
          "acl_token" => $try_agent_token.chomp,
          }
        }
        else {
          $_token_hash = {}
        }
      }
    }
  }
  else {
    $_token_hash = {
      "acl_token" => $agent_token,
    }
  }

  #
  # Generates: datacenter hash
  #
  if ($datacenter == undef) {
    $_datacenter = {}
  }
  else {
    $_datacenter = { "datacenter" => $datacenter }
  }

  #
  # Generates: serverhost (set in class_hash, below)
  #
  # Translates to retry_join
  if ($serverhost == undef) {
    if ($::servername == undef) {
      $_serverhost = $::fqdn
    }
    else {
      $_serverhost = $::servername
    }
  }
  else {
    $_serverhost = $serverhost
  }

  #
  # Generates: advertise (set in class_hash, below)
  #
  # Translates to advertise_addr 
  if ($advertise == undef) {
    $_advertise = $::ipaddress
  }
  else {
    $_advertise = $advertise
  }

  #
  # Generates: key_hash
  #
  # This is created after the first pass of bootstrap, essentially. See
  # bootstrap.pp.
  $keypath = '/etc/simp/bootstrap/consul/key'
  $keydata = file($keypath, "/dev/null")
  if ($keydata != undef) {
    $_key_hash = { 'encrypt' => $keydata.chomp }
  } else {
    $_key_hash = {}
  }

  #
  # Generates: cert_hash
  #
  if ($manage_pki == true) and ($bootstrap == false) {

    if (!defined(File['/etc/simp'])) {
      file { "/etc/simp":
        ensure => directory,
      }
    }
    file { "/etc/simp/consul":
      ensure => directory,
    }

    # If we're a server, use bootstrap certs by default
    if ($server == true) {
      if $cert_file {
        $_cert_file = $cert_file
      }
      else {
        $_cert_file = '/etc/simp/bootstrap/consul/server.dc1.consul.cert.pem'
      }
      if $key_file {
        $_key_file = $key_file
      }
      else {
        $_key_file = '/etc/simp/bootstrap/consul/server.dc1.consul.private.pem'
      }
      if $ca_file {
        $_ca_file = $ca_file
      }
      else {
        $_ca_file = '/etc/simp/bootstrap/consul/ca.pem'
      }

      file { '/etc/simp/consul/cert.pem':
        source => $_cert_file
      }
      file { '/etc/simp/consul/key.pem':
        source => $_key_file
      }
      file { '/etc/simp/consul/ca.pem':
        source => $_ca_file
      }
    }
    # If we're a client, use system puppet certs by default
    else {
      if $cert_file {
        $_cert_file = $cert_file
      }
      else {
        $_cert_file = "${puppet_cert_path}/certs/${::clientcert}.pem"
      }
      if $key_file {
        $_key_file = $key_file
      }
      else {
        $_key_file = "${puppet_cert_path}/private_keys/${::clientcert}.pem"
      }
      if $ca_file {
        $_ca_file = $ca_file
      }
      else {
        $_ca_file = "${puppet_cert_path}/certs/ca.pem"
      }

      file { '/etc/simp/consul/cert.pem':
        source => $_cert_file
      }
      file { '/etc/simp/consul/ca.pem':
        source => $_ca_file
      }
      file { '/etc/simp/consul/key.pem':
        source => $_key_file
      }

    }

    $_cert_hash = {
      "cert_file"              => '/etc/simp/consul/cert.pem',
      "ca_file"                => '/etc/simp/consul/ca.pem',
      "key_file"               => '/etc/simp/consul/key.pem',
      "verify_outgoing"        => true,
      "verify_incoming"        => true,
      "verify_server_hostname" => true,
    }
  }
  else {
    $_cert_hash = {}
  }

  #
  # Generates: class_hash, merged_hash
  #
  # Attempt to store bootstrap info into consul directly via libkv.
  # Use softfail to get around issues if the service isn't up
  $hash = lookup('consul::config_hash', { "default_value" => {} })
  if (SemVer.new($version) >= SemVer.new('0.7.0')) {
    $_uidir = {
      'ui' => true
    }
  } else {
    $_uidir = {
      'ui'     => true,
      'ui_dir' => '/opt/consul/ui'
    }
  }
  $class_hash =     {
    'server'         => $server,
    'node_name'      => $::hostname,
    'retry_join'     => [ $_serverhost ],
    'advertise_addr' => $_advertise,
    'addresses'      => {
    'http'           => $http_listen,
    'https'          => $https_listen,
    },
  }
  $merged_hash = $hash + $class_hash + $_datacenter + $config_hash + $_key_hash + $_token_hash + $_bootstrap_hash + $_cert_hash + $_uidir


  class { '::consul':
    config_hash => $merged_hash,
    version     => $version,
  }

  file { "/usr/bin/consul":
    target => "/usr/local/bin/consul",
  }
}
