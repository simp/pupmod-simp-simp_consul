#### Table of Contents
1. [Description](#description)
2. [Setup - Bootstrap](#setup)
3. [Usage](#usage)

## Description

The `simp_consul` module contains a profile which wraps around
[solarkennedy/puppet-consul](https://github.com/solarkennedy/puppet-consul)

## Setup

To begin using `simp_consul`, you must first bootstrap a Consul server. During
the bootstrap process, a `config_hash` will be generated, and passed to the
underlying consul class.  The process is detailed below.  The default beaker
suite contains an example implementaion of this process.

#### Bootstrap

Run `puppet apply simp_consul/bootstrap/consul.pp`. This will:

1. Generate the following artifacts, and store them in
   `/etc/simp/bootstrap/consul`:
  - `master_token`
    - `uuidgen` used to create the master token
  - `server.dc1.consul.<private,cert>.pem`, `ca.pem`
    - `puppet cert generate` used to create the Consul Cert/Key/CA

2. Instantiate the `simp_consul` class, with the following parameters:
  - `bootstrap     => true`
  - `server        => true`

3. Apply firewall rules if `firewall = true`

4. Instantiate the `::consul` class, with the following *default* parameters:
  - `server           => true`
  - `node_name        => $::hostname`
  - `address          => { 'http' => '127.0.0.1', https => '0.0.0.0' }`
  - `bootstrap_expect => 1`
  - `acl_master_token => /etc/pki/simp/bootstrap/consul/master_token`
  - `acl_token        => /etc/pki/simp/bootstrap/consul/master_token`
  - `retry_join       => $::servername` if defined, otherwise `$::fqdn`
  - `advertise_addr   => $::ipaddress`
  - `ui`              => `true`

5. Generate `/etc/simp/bootstrap/consul/key`

6. Set the `consul_bootstrapped` fact to `true`

## Usage

#### Server

Post bootstrap, include the `simp_consul` class, and set the following in
hieradata:

```yaml
---
libkv::url: 'consul://127.0.0.1:8500/puppet'
simp_consul::server: true
# This is only necessary if you have multiple NICs
simp_consul::advertise: "%{::ipaddress_eth1}"

classes:
  - simp_consul
```

Run `puppet agent -t`. This will:

1. Generate the libk and agent tokens,
   `/etc/simp/bootstrap/consul/libkv_token` and
   `/etc/simp/bootstrap/consul/agent_token`.

2. Copy `/etc/simp/bootstrap/consul/*.pem` to
   `/etc/simp/consul/<cert.pem,key.pem,ca.pem>`

3. Update the `::consul` `$config_hash` to include:
  - `encrypt                => /etc/simp/bootstrap/consul/key`
  - `cert_file              => /etc/simp/consul/cert.pem`
  - `ca_file                => /etc/simp/consul/ca.pem`
  - `key_file               => /etc/simp/consul/key.pem`
  - `verify_outgoing        => true`
  - `verify_incoming        => true`
  - `verify_server_hostname => true`


At this point, you can configure your server as you see fit.  See
`init.pp` for a list of configuration options.
