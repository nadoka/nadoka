#
# An example for drbot.nb
#
#

require 'drb/drb'

class Invokee
  include DRbUndumped
  
  def initialize invoker
    @invoker = invoker
    @invoker.add_observer self
  end

  def update *args
    p args
  end

  def destruct
    @invoker.delete_observer self
  end
end

uri = ARGV.shift || raise
DRb.start_service

invoker = DRbObject.new(nil, uri)

begin
  invokee = Invokee.new(invoker)
  p invoker
  puts '---'
  gets
ensure
  invokee.destruct
end


