#
# Copyright (c) 2004 SASADA Koichi <ko1 at atdot.net>
#
# This program is free software with ABSOLUTELY NO WARRANTY.
# You can re-distribute and/or modify this program under
# the same terms of the Ruby's lisence.
#
# 
# $Id: ndk_version.rb,v 1.3 2004/05/01 05:40:16 ko1 Exp $
# Create : K.S. 04/04/27 16:35:40
#

module Nadoka
  NDK_Version  = '0.5.3-devel'
  NDK_Created  = Time.now

  def self.version
    "Nadoka Ver.#{NDK_Version}" +
    " with Ruby #{RUBY_VERSION} (#{RUBY_RELEASE_DATE}) [#{RUBY_PLATFORM}]"
  end
end


