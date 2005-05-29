#
# Copyright (c) 2004-2005 SASADA Koichi <ko1 at atdot.net>
#
# This program is free software with ABSOLUTELY NO WARRANTY.
# You can re-distribute and/or modify this program under
# the same terms of the Ruby's lisence.
#
#
# $Id$
# Create : K.S. 04/05/01 02:04:18

require 'kconv'
require 'fileutils'

module Nadoka

  class LogWriter
    def initialize config, opts
      @opts    = opts
      @config  = config

      @time_fmt = opts[:time_format]
      @msg_fmts = opts[:message_format]
    end

    def write_log msg
      raise "override me"
    end

    def log_format msgobj
      @config.log_format @time_fmt, @msg_fmts, msgobj
    end

    def logging msgobj
      msg = log_format(msgobj)
      return if msg.empty?
      write_log msg
    end
  end

  class LogUnWriter < LogWriter
    def logging _
    end
  end
  
  class IOLogWriter < LogWriter
    def initialize config, opts
      super
      @io = opts[:io]
    end
    
    def write_log msg
      @io.puts msg
    end
  end

  class FileLogWriter < LogWriter
    def initialize config, opts
      super
      @filename_fmt = opts[:file]
    end

    def logging msgobj
      msg = log_format(msgobj)
      return if msg.empty?
      write_log_file make_logfilename(@filename_fmt, msgobj[:ch] || ''), msg
    end
    
    def write_log_file basefile, msg
      basedir  = File.expand_path(@config.log_dir) + '/'
      logfile  = File.expand_path(basefile, basedir)
      ldir     = File.dirname(logfile) + '/'
      
      if !FileTest.directory?(ldir)
        raise "insecure directory: #{ldir} (pls check rc file.)" if /\A#{Regexp.quote(basedir)}/ !~ ldir
        # make directory recursively
        FileUtils.mkdir_p(ldir)
      end
      
      open(logfile, 'a'){|f|
        f.flock(File::LOCK_EX)
        f.puts msg
      }
    end

    def make_logfilename tmpl, ch
      @config.make_logfilename tmpl, ch
    end
  end

  class NDK_Logger
    class MessageStore
      def initialize limit
        @limit = limit
        @pool  = []
      end

      attr_reader :pool
      
      def limit=(lim)
        @limit = lim
      end

      def truncate
        while @pool.size > @limit
          @pool.shift
        end
      end

      def push msgobj
        truncate
        @pool.push msgobj
      end

      def clear
        @pool.clear
      end
    end

    class MessageStoreByTime < MessageStore
      def truncate
        lim = Time.now.to_i - @limit
        while true
          if @pool[0][:time].to_i < lim
            @pool.shift
          else
            break
          end
        end
      end
    end

    class MessageStores
      def initialize type, lim, config
        @limit  = lim
        @class  = type == :time ? MessageStoreByTime : MessageStore
        @config = config
        @pools  = {}
      end

      attr_reader :pools

      def push msgobj
        ch = msgobj[:ccn]
        
        unless pool = @pools[ch]
          limit = (@config.channel_info[ch] && @config.channel_info[ch][:backloglines]) ||
                   @limit
          @pools[ch] = pool = @class.new(limit)
        end
        pool.push msgobj
      end

      def each_channel_pool
        @pools.each{|ch, store|
          yield ch, store.pool
        }
      end
    end
    
    
    def initialize manager, config
      @manager = manager
      @config  = config
      @dlog    = @config.debug_log
      @message_stores = MessageStores.new(:size, @config.backlog_lines, @config)
    end

    attr_reader :message_stores
    
    # debug message
    def dlog msg
      if @config.loglevel >= 3
        msgobj = make_msgobj msg, 'DEBUG'
        @config.debug_logwriter.logging msgobj
      end
    end
    alias debug dlog

    # system message
    def slog msg, nostamp = false
      msgobj = make_msgobj(msg, 'SYSTEM', nostamp)
      if @config.loglevel >= 2
        @config.system_logwriter.logging msgobj
        @message_stores.push msgobj
      end

      str = @config.system_logwriter.log_format(msgobj)
      @manager.send_to_clients Cmd.notice(@manager.state.nick, str) if @manager.state
      dlog str
    end

    # channel message
    def clog ch, msg, nostamp = false
      clog_msgobj ch, make_msgobj(msg, 'SIMPLE', nostamp)
    end

    # other irc log message
    def olog msg
      olog_msgobj make_msgobj(msg, 'OTHER')
    end

    #########################################
    def make_msgobj msg, type = msg.command, nostamp = false
      msgobj = {
        :time    => Time.now,
        :type    => type,
        :orig    => msg,
        :nostamp => nostamp,
      }

      msgobj
    end

    def clog_msgobj ch, msgobj
      if msgobj[:ccn] == :__talk__
        logwriter = @config.talk_logwriter
      else
        logwriter = (@config.channel_info[ch] && @config.channel_info[ch][:logwriter]) ||
                     @config.default_logwriter
      end

      @message_stores.push msgobj
      logwriter.logging msgobj
    end

    def olog_msgobj msgobj
      if @config.loglevel >= 1
        @config.system_logwriter.logging msgobj
        @message_stores.push msgobj
      end
    end
    
    # logging
    def logging msg
      user = @manager.nick_of(msg)
      rch = msg.params[0]
      ch_ = ch = @config.canonical_channel_name(rch)

      msgobj = make_msgobj(msg)
      msgobj[:ch]   = rch  # should be raw
      msgobj[:ccn]  = ch
      msgobj[:user] = user
      msgobj[:msg]  = msg.params[1]
      
      case msg.command
      when 'PRIVMSG', 'NOTICE', 'TOPIC', 'JOIN', 'PART', 'QUIT'
        unless /\A[\&\#\+\!]/ =~ ch # talk?
          msgobj[:sender]   = user
          msgobj[:receiver] = rch
          msgobj[:ccn]      = :__talk__
        end
        clog_msgobj ch, msgobj

      when  'NICK'
        @manager.state.current_channels.each{|ch, chs|
          if chs.member.has_key? rch
            msgobj[:user]    = user
            msgobj[:newnick] = rch
            clog_msgobj ch, msgobj
          end
        }
        
      when 'MODE'
        msgobj[:msg] = msg.params[1..-1].join(', ')

        if @manager.state.current_channels[ch]
          clog_msgobj ch, msgobj
        else
          olog_msgobj msgobj
        end
        
      when 'KICK'
        msgobj[:kicker] = msg.params[1]
        msgobj[:msg]    = msg.params[2]
        clog_msgobj ch, msgobj
        
      when /^\d+/
        # reply
        str = msg.command + ' ' + msg.params.join(' ')
        olog str
        
      else
        # other command
        olog msg.to_s
      end
    end
    

    ###
  end
end


