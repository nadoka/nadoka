#!/usr/bin/env ruby
#
##
## Nadoka:
##  Irc Client Server Program
##
#
# Copyright (c) 2004-2005 SASADA Koichi <ko1 at atdot.net>
#
# This program is free software with ABSOLUTELY NO WARRANTY.
# You can re-distribute and/or modify this program under
# the same terms of the Ruby's license.
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

if ENV.key?('NOTIFY_SOCKET')
  require 'lib/notify_socket'
  $NDK_NOTIFY_SOCKET = NotifySocket.new
else
  $NDK_NOTIFY_SOCKET = Object.new
  def $NDK_NOTIFY_SOCKET.method_missing(*)
    # ignore
  end
end

unless defined? Process.daemon
  def Process.daemon(nochdir = nil, noclose = nil)
    exit!(0) if fork
    Process.setsid
    exit!(0) if fork
    Dir.chdir('/') unless nochdir
    File.umask(0)
    unless noclose
      STDIN.reopen('/dev/null')
      STDOUT.reopen('/dev/null', 'w')
      STDERR.reopen('/dev/null', 'w')
    end
  end
end

rcfile = nil
pidfile = nil
daemon = false
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
  opts.on("--daemon", "run as daemon"){
    daemon = true
  }
  opts.on("--pid [PIDFILE]", "Put process pid into PIDFILE"){|f|
    pidfile = f
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

if daemon
  Process.daemon
end

if pidfile
  open(pidfile, "w") {|f| f.puts Process.pid }
end

begin
  GC.start
  Nadoka::NDK_Server.new(rcfile).start
rescue Nadoka::NDK_QuitProgram
  $NDK_NOTIFY_SOCKET.stopping!
rescue Nadoka::NDK_RestartProgram
  $NDK_NOTIFY_SOCKET.reloading!
  GC.start
  ObjectSpace.each_object(Socket) {|sock| sock.close}
  retry
rescue Exception => e
  $NDK_NOTIFY_SOCKET.stopping!
  open('nadoka_fatal_error', 'w'){|f|
    f.puts e
    f.puts e.backtrace.join("\n")
  } 
end

if pidfile
  File.unlink(pidfile)
end

end

