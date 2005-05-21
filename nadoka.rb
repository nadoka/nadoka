#!/usr/bin/env ruby
#
##
## Nadoka:
##  Irc Client Server Program
##
#
# Copyright (c) 2004 SASADA Koichi <ko1 at atdot.net>
#
# This program is free software with ABSOLUTELY NO WARRANTY.
# You can re-distribute and/or modify this program under
# the same terms of the Ruby's lisence.
#
#
# $Id$
# Create : K.S. 03/07/10 20:29:07
#


$LOAD_PATH.unshift File.dirname(__FILE__)
require 'ndk/version'

if $0 == __FILE__

require 'optparse'

require 'ndk/server'
require 'ndk/bot'

$stdout.sync=true
$NDK_Debug  = false

rcfile = nil
optparse = OptionParser.new{|opts|
  opts.banner = "Usage: ruby #{$0} [options]"

  opts.separator ""
  opts.separator "Require options:"

  opts.on("-r", "--rc [RCFILE]",
          "Specify rcfile(required)"){|f|
    rcfile = f
  }

  opts.separator ""
  opts.separator "Optional:"

  opts.on("-d", "--debug",
          "Debug Nadoka"){
    $NDK_Debug = true
    $DEBUG = true
    
    puts 'Enter Nadoka Debug mode'
  }

  opts.separator ""
  opts.separator "Common options:"

  opts.on_tail("-h", "--help", "Show this message"){
    puts Nadoka.version
    puts opts
    exit
  }
  opts.on_tail("-v", "--version", "Show version"){
    puts Nadoka.version
  }
}
optparse.parse!(ARGV)

unless rcfile
  puts Nadoka.version
  puts optparse
  exit
end

begin
  GC.start
  Nadoka::NDK_Server.new(rcfile).start
rescue Nadoka::NDK_QuitProgram
  #
rescue Nadoka::NDK_RestartProgram
  retry
end

end

