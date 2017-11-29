require 'spec_helper'

describe 'simp_consul' do
  context 'supported operating systems' do
    on_supported_os.each do |os, facts|
      context "on #{os}" do

        let(:facts) do
	        facts.merge({
            :servername => 'foo.bar.baz'
	      })
        end

        it { is_expected.to compile.with_all_deps }
        it { is_expected.to contain_class('simp_consul') }

      end
    end
  end
end

