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
  NDK_Version  = '0.5.4-devel'
  NDK_Created  = Time.now

  def self.version
    "Nadoka Ver.#{NDK_Version}" +
    " with Ruby #{RUBY_VERSION} (#{RUBY_RELEASE_DATE}) [#{RUBY_PLATFORM}]"
  end
end


