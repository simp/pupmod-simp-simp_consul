require 'spec_helper_consul'

test_name 'simp_consul test'

def set_profile_data_on(host, hiera_yaml, profile_data)

  Dir.mktmpdir do |dir|
    tmp_yaml = File.join(dir, 'hiera.yaml')
    File.open(tmp_yaml, 'w') do |fh|
      fh.puts hiera_yaml
    end
    host.do_scp_to(tmp_yaml, '/etc/puppetlabs/puppet/hiera.yaml', {})
  end
  if (profile_data.class.to_s == "Hash")
    profile_data.each do |filename, data|
      dirname = File.dirname(filename);
      Dir.mktmpdir do |dir|
        unless (Dir.exists?(File.join(dir, dirname)))
          Dir.mkdir(File.join(dir, dirname))
        end
        File.open(File.join(dir, filename), 'w') do |fh|
          fh.puts(data)
          fh.flush

          file = "/etc/puppetlabs/code/environments/production/hieradata/#{filename}"
          on(host, "sudo sh -c 'mkdir -p /etc/puppetlabs/code/environments/production/hieradata/#{dirname}'")
          host.do_scp_to(File.join(dir, filename), file, {})
        end
      end
    end
  else
    Dir.mktmpdir do |dir|
      File.open(File.join(dir, "default" + '.yaml'), 'w') do |fh|
        fh.puts(profile_data)
        fh.flush

        default_file = "/etc/puppetlabs/code/environments/production/hieradata/default.yaml"

        host.do_scp_to(dir + "/default.yaml", default_file, {})
      end
    end
  end
end

describe 'simp_consul test' do

  ["el7", "el6"].each do |platform|
    servers = hosts_with_name(hosts, "#{platform}server")
    servers.each do |server|
      on(server, "puppet config set trusted_server_facts true")
      on(server, "puppet resource package puppetserver ensure=installed")
      on(server, "puppet resource service puppetserver ensure=running enable=true")
      fqdn = on(server, 'facter fqdn').stdout.strip
      on(server, "echo '*' > /etc/puppetlabs/puppet/autosign.conf")
      server.do_scp_to('./spec/acceptance/site.pp', "/etc/puppetlabs/code/environments/production/manifests/site.pp", {})

      context 'server setup' do

        let(:hiera_yaml) { <<-EOS
---
:backends:
  - yaml
:yaml:
  :datadir: '/etc/puppetlabs/code/environments/production/hieradata'
:hierarchy:
  - 'hosts/%{trusted.certname}'
  - 'default'
                           EOS
        }

        let(:default_hieradata) { <<-EOS
libkv::url: 'consul://127.0.0.1:8500/puppet'
simp_consul::server: false
simp_consul::advertise: "%{::ipaddress_eth1}"
                                  EOS
        }
        let(:server_hieradata) { <<-EOS
libkv::url: 'consul://127.0.0.1:8500/puppet'
simp_consul::server: true
simp_consul::advertise: "%{::ipaddress_eth1}"
                                 EOS
        }

        it 'should set certname' do
          on(server, "sudo /opt/puppetlabs/bin/puppet config set certname #{fqdn}", :catch_failures => true)
        end

        it 'should set profile data' do
          set_profile_data_on(server, hiera_yaml, { "default.yaml" => default_hieradata, "hosts/#{fqdn}.yaml" => server_hieradata })
        end

        it 'should apply bootstrap' do
          on(server, "sudo /opt/puppetlabs/bin/puppet apply /etc/puppetlabs/code/environments/production/modules/simp_consul/bootstrap/consul.pp")
        end

        it 'should apply default manifest' do
          on(server, "sudo /opt/puppetlabs/bin/puppet agent -t --server #{fqdn}", :catch_failures => true, :acceptable_exit_codes => [0,2])
        end

        it 'should be idempotent' do
          on(server, "sudo /opt/puppetlabs/bin/puppet agent -t --server #{fqdn}", :catch_changes => true)
        end

        it 'should create puppet consul value' do
          on(server, "consul kv put puppet/test consul_test_value")
        end

        it 'should contain file /usr/bin/consul-acl' do
          result = on(server, "ls -la /usr/bin/consul-acl")
          expect(result.stdout).to include("rwxr-xr-x")
        end

        it 'should contain file /usr/bin/consul-create-acl' do
          result = on(server, "ls -la /usr/bin/consul-create-acl")
          expect(result.stdout).to include("rwxr-xr-x")
        end

        it 'should create libkv_token' do
          result = on(server,"ls -la /etc/simp/bootstrap/consul")
          expect(result.stdout).to include("libkv_token")
        end

        it 'should create agent_token' do
          result = on(server, "ls -la /etc/simp/bootstrap/consul")
          expect(result.stdout).to include("agent_token")
        end

        it 'should contain file /usr/bin/consul-acl' do
          result = on(server, "ls -la /usr/bin/consul-acl")
          expect(result.stdout).to include("rwxr-xr-x")
        end

        it 'should contain file /usr/bin/consul-create-acl' do
          result = on(server, "ls -la /usr/bin/consul-create-acl")
          expect(result.stdout).to include("rwxr-xr-x")
        end

        it 'should return puppet/test consul value' do
          result = on(server, "consul kv get puppet/test")
          expect(result.stdout).to include("consul_test_value")
        end
      end

      context 'firewall setup' do

        let(:hiera_yaml) { <<-EOS
---
:backends:
  - yaml
:yaml:
  :datadir: '/etc/puppetlabs/code/environments/production/hieradata'
:hierarchy:
  - 'hosts/%{trusted.certname}'
  - 'default'
                           EOS
        }

        let(:default_hieradata) { <<-EOS
libkv::url: 'consul://127.0.0.1:8500/puppet'
simp_consul::server: false
simp_consul::advertise: "%{::ipaddress_eth1}"
                                  EOS
        }
        let(:firewall_hieradata) { <<-EOS
libkv::url: 'consul://127.0.0.1:8500/puppet'
simp_consul::server: true
simp_consul::firewall: true
simp_consul::advertise: "%{::ipaddress_eth1}"
                                   EOS
        }

        it 'should set profile data' do
          set_profile_data_on(server, hiera_yaml, { "default.yaml" => default_hieradata, "hosts/#{fqdn}.yaml" => firewall_hieradata })
        end

        it 'should apply bootstrap' do
          on(server, "sudo /opt/puppetlabs/bin/puppet apply /etc/puppetlabs/code/environments/production/modules/simp_consul/bootstrap/consul.pp")
        end

        it 'should apply default manifest' do
          on(server, "sudo /opt/puppetlabs/bin/puppet agent -t --server #{fqdn}", :catch_failures => true, :acceptable_exit_codes => [0,2])
        end

        it 'should be idempotent' do
          on(server, "sudo /opt/puppetlabs/bin/puppet agent -t --server #{fqdn}", :catch_changes => true)
        end

        it 'should be listening on TCP ports 8300, 8301, 8302, 8500, and 8600' do
          result = on(server, "netstat -plnt")
          expect(result.stdout).to include("8300", "8301", "8302", "8500", "8600")
        end

        it 'should be listening on UDP ports 8301, 8302, and 8600' do 
          result = on(server, "netstat -plnu")
          expect(result.stdout).to include("8301", "8302", "8600")
        end
      end

      agents = hosts_with_name(hosts, "#{platform}agent")
      agents.each do |agent|
        on(agent, "puppet config set trusted_server_facts true")

        context 'agent test' do

          it 'should apply cleanly' do
            on(agent, "sudo /opt/puppetlabs/bin/puppet agent -t --server #{fqdn}", :catch_failures => true, :acceptable_exit_codes => [0,2])
          end

          it 'should be idempotent' do
            on(agent, "sudo /opt/puppetlabs/bin/puppet agent -t --server #{fqdn}", :catch_changes => true)
          end

          it 'should not return consul kv for puppet' do
            result = on(agent, "consul kv get puppet/test", :accept_all_exit_codes => true)
            expect(result.exit_code).to_not eq(0)
          end
        end
      end
    end
  end
end
# vim: set expandtab ts=2 sw=2:
