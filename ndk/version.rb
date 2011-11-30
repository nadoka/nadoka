#
# Copyright (c) 2004-2005 SASADA Koichi <ko1 at atdot.net>
#
# This program is free software with ABSOLUTELY NO WARRANTY.
# You can re-distribute and/or modify this program under
# the same terms of the Ruby's license.
#
# 
# $Id$
# Create : K.S. 04/04/27 16:35:40
#

module Nadoka
  NDK_Version  = '0.7.9'
  NDK_Created  = Time.now

  if File.directory?(File.expand_path('../../.git', __FILE__))
    NDK_Version.concat("+git")
  end
  if /trunk/ =~ '$HeadURL$'
    NDK_Version.concat('-trunk')
    rev = '-'
    $LOAD_PATH.each{|path|
      path = path + '/ChangeLog'
      if FileTest.exist?(path)
        if /^\# ChangeLog of Nadoka\(\$Rev: (\d+) \$\)$/ =~ open(path){|f| s = f.gets}
          rev = "rev: #{$1}"
          break
        end
      end
    }
    NDK_Version.concat(" (#{rev})")
  end
  
  def self.version
    "Nadoka Ver.#{NDK_Version}" +
    " with Ruby #{RUBY_VERSION} (#{RUBY_RELEASE_DATE}) [#{RUBY_PLATFORM}]"
  end
end

if __FILE__ == $0
  puts Nadoka::NDK_Version
end
