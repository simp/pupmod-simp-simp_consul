# _Description_
#
# Return the number of consul servers
#
Facter.add('consul_members') do
  setcode do
    if Facter::Util::Resolution.which('consul') then
      Facter::Util::Resolution.exec('consul members').split("\n").grep(/server/).grep(/dc1/).size
    end
  end
end

