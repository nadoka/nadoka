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
  VERSION  = '0.9.2'
  NDK_Version  = VERSION.dup
  NDK_Created  = Time.now

  if File.directory?(File.expand_path('../../.git', __FILE__))
    git_describe = nil
    Dir.chdir(File.expand_path('../..', __FILE__)) do
      git_describe = `git describe --tags --long --dirty=-dt`
      if $?.success?
        git_describe = "(#{git_describe.strip})"
      else
        git_describe = nil
      end
    end
    NDK_Version.concat("+git#{git_describe}")
  end
  if /trunk/ =~ '$HeadURL$'
    NDK_Version.concat('-trunk')
    rev = '-'
    $LOAD_PATH.each{|path|
      path = path + '/ChangeLog'
      if FileTest.exist?(path)
        if /^\# ChangeLog of Nadoka\(\$Rev: (\d+) \$\)$/ =~ open(path){|f| f.gets}
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
