#
# Copyright (c) 2004 SASADA Koichi <ko1 at atdot.net>
#
# This program is free software with ABSOLUTELY NO WARRANTY.
# You can re-distribute and/or modify this program under
# the same terms of the Ruby's lisence.
#
# 
# $Id$
# Create : K.S. 04/04/27 16:35:40
#

module Nadoka
  NDK_Version  = '0.6.5'
  NDK_Created  = Time.now

  if /trunk/ =~ '$HeadURL$'
    NDK_Version.concat('-trunk')
    rev = '-'
    $LOAD_PATH.each{|path|
      path = path + '/ChangeLog'
      if FileTest.exist?(path)
        if /^\# ChangeLog of Nadoka\(\$Rev: (\d+) \$\)$/ =~ open(path){|f| s = f.gets}
          rev = "Rev: #{$1}"
          break
        end
      end
    }
    NDK_Version.concat("(#{rev})")
  end
  
  def self.version
    "Nadoka Ver.#{NDK_Version}" +
    " with Ruby #{RUBY_VERSION} (#{RUBY_RELEASE_DATE}) [#{RUBY_PLATFORM}]"
  end
end

