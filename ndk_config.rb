#!/usr/bin/env ruby
#
# Copyright (c) 2004 SASADA Koichi <ko1 at atdot.net>
#
# This program is free software with ABSOLUTELY NO WARRANTY.
# You can re-distribute and/or modify this program under
# the same terms of the Ruby's lisence.
#
#
# $Id$
# Create : K.S. 04/04/17 16:50:33
#
#
# You can check RCFILE with following command:
#
#   ruby ndk_config.rb [RCFILE]
#

require 'uri'
require 'socket'
require 'kconv'

require 'ndk_logger'

module Nadoka
  
  class NDK_ConfigBase
    # system
    # 0: quiet, 1: normal, 2: system, 3: debug
    Loglevel     = 2
    Setting_name = 'DefaultSetting',
    
    # client server
    Client_server_port = 6667
    Client_server_host = nil
    Client_server_pass = 'NadokaPassWord' # or nil
    Client_server_acl  = nil
    ACL_Object = nil
    
    # 
    Server_list = [
    # { :host => '127.0.0.1', :port => 6667, :pass => nil }
    ]
    Servers = []

    Reconnect_delay    = 30
    
    Default_channels   = []
    Login_channels     = []

    #
    User       = ENV['USER'] || ENV['USERNAME'] || 'nadokatest'
    Nick       = 'ndkusr'
    Hostname   = Socket.gethostname
    Servername = '*'
    Realname   = 'nadoka user'
    Mode       = nil
    
    Away_Message = 'away'
    Away_Nick    = nil

    Quit_Message = 'bye'
    
    #
    Channel_info = {}
    # log
    Default_log = '${setting_name}-${channel_name}-%y%m%d.log'
    System_log  = '${setting_name}-system_log'
    Debug_log   = $stdout
    FilenameEncoding = 'euc'
    
    Backlog_lines = 20
    Log_TimeFormat= '%y/%m/%d-%H:%M:%S'
    
    # dirs
    Plugins_dir = './plugins'
    Log_dir     = './log'
    
    # bots
    BotFiles    = []
    BotConfig   = {}

    # filters
    Privmsg_Filter = []
    Notice_Filter  = []

    # ...
    Privmsg_Filter_light = []
    Nadoka_server_name   = 'NadokaProgram'
    
    def self.inherited subklass
      ConfigClass << subklass
    end
  end
  ConfigClass = [NDK_ConfigBase]
  BotClass = []
  
  class NDK_Config
    NDK_ConfigBase.constants.each{|e|
      eval %Q{
        def #{e.downcase}
          @config['#{e.downcase}'.intern]
        end
      }
    }
    
    def initialize manager, rcfile = nil
      @manager = manager
      @bots = []
      load_config(rcfile || './nadokarc')
    end
    attr_reader :config, :bots, :logger

    def remove_previous_setting
      # remove setting class
      klass = ConfigClass.shift
      while k = ConfigClass.shift
        Object.module_eval{
          remove_const(k.name)
        }
      end
      ConfigClass.push(klass)

      # remove bot class
      while k = BotClass.shift
        Object.module_eval{
          remove_const(k.name)
        }
      end
      # destruct bot instances
      @bots.each{|bot|
        bot.bot_destruct
      }
      
      GC.start
    end
    
    def load_config(rcfile)
      remove_previous_setting
      
      load(rcfile) if rcfile
      
      @config = {}
      klass = ConfigClass.last
      klass.constants.each{|e|
        @config[e.downcase.intern] = klass.const_get(e)
      }

      if $NDK_Debug
        @config[:loglevel] = 3
      end
      
      @logger = NDK_Logger.new(@manager, self)
      @logger.slog "load config: #{rcfile}"

      if svrs = klass.const_get(:Servers)
        svl = []
        svrs.each{|si|
          ports = si[:port] || 6667
          host  = si[:host]
          pass  = si[:pass]
          if ports.respond_to? :each
            ports.each{|port|
              svl << {:host => host, :port => port, :pass => pass}
            }
          else
            svl <<   {:host => host, :port => ports, :pass => pass}
          end
        }
        @config[:server_list] = svl
      end

      # treat with channel information
      if chs = klass.const_get(:Channel_info)
        dchs = []
        lchs = []
        cchs = {}
        
        chs.each{|ch, setting|
          ch = identical_channel_name(ch)
          
          if !setting[:timing] || setting[:timing] == :startup
            dchs << ch
          elsif setting[:timing] == :login
            lchs << ch
          end
          cchs[ch] = setting
        }
        chs.replace cchs
        @config[:default_channels] = dchs
        @config[:login_channels]   = lchs
      end

      # acl setting
      if @config[:client_server_acl] && !@config[:acl_object]
        require 'drb/acl'
        
        acl = @config[:client_server_acl].strip.split(/\s+/)
        @config[:acl_object] = ACL.new(acl)
        logger.slog "ACL: #{acl.join(' ')}"
      end

      # load bots
      @config[:botfiles].each{|file|
        load_botfile file
      }
      
      @config[:botconfig].keys.each{|bk|
        bkn = bk.to_s
        unless BotClass.any?{|e| e.name == bkn}
          if @config[:botfiles]
            raise "No such BotClass: #{bkn}"
          else
            load_botfile "#{bkn.downcase}.nb"
          end
        end
      }
      
      @bots = BotClass.map{|bk|
        bkname = bk.name.intern
        if @config[:botconfig].has_key? bkname
          if (cfg = @config[:botconfig][bkname]).kind_of? Array
            cfg.map{|c|
              make_bot_instance bk, c
            }
          else
            make_bot_instance bk, cfg
          end
        else
          make_bot_instance bk, nil
        end
      }.flatten
      
    end
    
    def canonical_channel_name ch
      ch = ch.sub(/^\!.{5}/, '!')
      identical_channel_name ch
    end

    def identical_channel_name ch
      # use 4 gsub() because of the compatibility of RFC2813(3.2)
      ch.toeuc.downcase.gsub( "[", "{" ).
                        gsub( "]", "}" ).
                        gsub( "\\", "|" ).
                        gsub( "~", "^" ).tojis
    end
    
    def make_bot_instance bk, cfg
      bot = bk.new @manager, self, cfg || {}
      @logger.slog "bot instance: #{bot}"
      bot
    end
    
    def load_botfile file
      loaded = false
      
      if @config[:plugins_dir].respond_to? :each
        @config[:plugins_dir].each{|dir|
          if load_file "#{dir}/#{file}.nb"
            loaded = true
            break
          end
        }
      else
        loaded = load_file "#{@config[:plugins_dir]}/#{file}.nb"
      end

      unless loaded
        raise "No such bot file: #{file}"
      end
    end

    def load_file file
      if FileTest.exist? file
        load file
        true
      else
        false
      end
    end
    
  end
end

if $0 == __FILE__
  require 'pp'
  pp Nadoka::NDK_Config.new(nil, ARGV.shift)
end

