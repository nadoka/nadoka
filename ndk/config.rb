#
# Copyright (c) 2004-2005 SASADA Koichi <ko1 at atdot.net>
#
# This program is free software with ABSOLUTELY NO WARRANTY.
# You can re-distribute and/or modify this program under
# the same terms of the Ruby's license.
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

require 'ndk/logger'

module Nadoka
  
  class NDK_ConfigBase
    # system
    # 0: quiet, 1: normal, 2: system, 3: debug
    Loglevel     = 2
    Setting_name = nil
    
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

    Reconnect_delay    = 150
    
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

    Quit_Message = "Quit Nadoka #{::Nadoka::NDK_Version} - http://www.atdot.net/nadoka/"
    
    #
    Channel_info = {}
    # log
    
    Default_log = {
      :file           => '${setting_name}-${channel_name}/%y%m%d.log',
      :time_format    => '%H:%M:%S',
      :message_format => {
        'PRIVMSG' => '<{nick}> {msg}',
        'NOTICE'  => '{{nick}} {msg}',
        'JOIN'    => '+ {nick} ({prefix:user}@{prefix:host})',
        'NICK'    => '* {nick} -> {newnick}',
        'QUIT'    => '- {nick} (QUIT: {msg}) ({prefix:user}@{prefix:host})',
        'PART'    => '- {nick} (PART: {msg}) ({prefix:user}@{prefix:host})',
        'KICK'    => '- {nick} kicked by {kicker} ({msg})',
        'MODE'    => '* {nick} changed mode ({msg})',
        'TOPIC'   => '<{ch} TOPIC> {msg} (by {nick})',
        'SYSTEM'  => '[NDK] {orig}',
        'OTHER'   => '{orig}',
        'SIMPLE'  => '{orig}',
      },
    }

    System_log = {
      :file           => '${setting_name}-system.log',
      :time_format    => '%y/%m/%d-%H:%M:%S',
      :message_format => {
        'PRIVMSG' => '{ch} <{nick}> {msg}',
        'NOTICE'  => '{ch} {{nick}} {msg}',
        'JOIN'    => '{ch} + {nick} ({prefix:user}@{prefix:host})',
        'NICK'    => '{ch} * {nick} -> {newnick}',
        'QUIT'    => '{ch} - {nick} (QUIT: {msg}) ({prefix:user}@{prefix:host})',
        'PART'    => '{ch} - {nick} (PART: {msg}) ({prefix:user}@{prefix:host})',
        'KICK'    => '{ch} - {nick} kicked by {kicker} ({msg})',
        'MODE'    => '{ch} * {nick} changed mode ({msg})',
        'TOPIC'   => '{ch} <{ch} TOPIC> {msg} (by {nick})',
        'SYSTEM'  => '[NDK] {orig}',
        'OTHER'   => nil,
        'SIMPLE'  => nil,
      },
    }

    Debug_log = {
      :io             => $stdout,
      :time_format    => '%y/%m/%d-%H:%M:%S',
      :message_format => System_log[:message_format],
    }

    Talk_log = {
      :file           => '${setting_name}-talk/%y%m%d.log',
      :time_format    => Default_log[:time_format],
      :message_format => {
        'PRIVMSG' => '[{sender} => {receiver}] {msg}',
        'NOTICE'  => '{{sender} -> {receiver}} {msg}',
      }
    }

    System_Logwriter  = nil
    Debug_Logwriter   = nil
    Default_Logwriter = nil
    Talk_Logwriter    = nil

    BackLog_Lines     = 20

    # file name encoding setting
    # 'euc' or 'sjis' or 'jis' or 'utf8'
    FilenameEncoding =
      case RUBY_PLATFORM
      when /mswin/, /cygwin/, /mingw/
        'sjis'
      else
        if /UTF-?8/i =~ ENV['LANG']
          'utf8'
        else
          'euc'
        end
      end
    
    # dirs
    Plugins_dir = './plugins'
    Log_dir     = './log'
    
    # bots
    BotConfig   = []

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


      # clear required files
      RequiredFiles.replace []

      # remove current NadokaBot
      Object.module_eval %q{
        remove_const :NadokaBot
        module NadokaBot
          def self.included mod
            Nadoka::NDK_Config::BotClasses['::' + mod.name.downcase] = mod
          end
        end
      }
      
      # clear bot class
      BotClasses.each{|k, v|
        Object.module_eval{
          if /\:\:/ !~ k.to_s && const_defined?(v.name)
            remove_const(v.name)
          end
        }
      }
      BotClasses.clear
      
      # destruct bot instances
      @bots.each{|bot|
        bot.bot_destruct
      }
      @bots = []

      GC.start
    end

    def load_bots
      # for compatibility
      return load_bots_old if @config[:botconfig].kind_of? Hash
      @bots = @config[:botconfig].map{|bot|
        next nil if bot[:disable]
        if bot.kind_of? Hash
          name = bot[:name]
          cfg  = bot
          raise "No bot name specified. Check rcfile." unless name
        else
          name = bot
          cfg  = nil
        end
        load_botfile name.to_s.downcase
        make_bot_instance name, cfg
      }.compact
    end

    # for compatibility
    def load_bots_old
      (@config[:botfiles] + (@config[:defaultbotfiles]||[])).each{|file|
        load_botfile file
      }
      
      @config[:botconfig].keys.each{|bk|
        bkn = bk.to_s
        bkni= bkn.intern
        
        unless BotClasses.any?{|n, c| n == bkni}
          if @config[:botfiles]
            raise "No such BotClass: #{bkn}"
          else
            load_botfile "#{bkn.downcase}.nb"
          end
        end
      }
      
      @bots = BotClasses.map{|bkname, bk|
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

    def server_setting
      if svrs = @config[:servers]
        svl = []
        svrs.each{|si|
          ports = si[:port] || 6667
          host  = si[:host]
          pass  = si[:pass]
          if ports.respond_to? :each
            ports.each{|port|
              svl << {:host => host, :port => port,  :pass => pass}
            }
          else
            svl <<   {:host => host, :port => ports, :pass => pass}
          end
        }
        @config[:server_list] = svl
      end
    end

    def make_logwriter log
      return unless log
      
      case log
      when Hash
        if    log.has_key?(:logwriter)
          return log[:logwriter]
        elsif log.has_key?(:logwriterclass)
          klass = log[:logwriterclass]
        elsif log.has_key?(:io)
          klass = IOLogWriter
        elsif log.has_key?(:file)
          klass = FileLogWriter
        else
          klass = FileLogWriter
        end
        opts = @config[:default_log].merge(log)
        klass.new(self, opts)
        
      when String
        opts = @config[:default_log].dup
        opts[:file] = log
        FileLogWriter.new(self, opts)
        
      when IO
        opts = @config[:default_log].dup
        opts[:io] = log
        IOLogWriter.new(self, opts)
        
      else
        raise "Unknown LogWriter setting"
      end
    end

    def make_default_logwriter
      if @config[:default_log].kind_of? Hash
        dl = @config[:default_log]
      else
        # defult_log must be Hash
        dl = @config[:default_log]
        @config[:default_log] = NDK_ConfigBase::Default_log.dup
      end
      
      @config[:default_logwriter] ||= make_logwriter(dl)
      @config[:system_logwriter]  ||= make_logwriter(@config[:system_log])
      @config[:debug_logwriter]   ||= make_logwriter(@config[:debug_log])
      @config[:talk_logwriter]    ||= make_logwriter(@config[:talk_log])
    end
    
    def channel_setting
      # treat with channel information
      if chs = @config[:channel_info]
        dchs = []
        lchs = []
        cchs = {}
        
        chs.each{|ch, setting|
          ch = identical_channel_name(ch)
          setting = {} unless setting.kind_of?(Hash)
          
          if !setting[:timing] || setting[:timing] == :startup
            dchs << ch
          elsif setting[:timing] == :login
            lchs << ch
          end

          # log writer
          setting[:logwriter] ||= make_logwriter(setting[:log]) || @config[:default_logwriter]
          
          cchs[ch] = setting
        }
        chs.replace cchs
        @config[:default_channels] = dchs
        @config[:login_channels]   = lchs
      end
    end

    def acl_setting
      if @config[:client_server_acl] && !@config[:acl_object]
        require 'drb/acl'
        
        acl = @config[:client_server_acl].strip.split(/\s+/)
        @config[:acl_object] = ACL.new(acl)
        @logger.slog "ACL: #{acl.join(' ')}"
      end
    end

    def load_config(rcfile)
      load(rcfile) if rcfile
      
      @config = {}
      klass = ConfigClass.last

      klass.ancestors[0..-3].reverse_each{|kl|
        kl.constants.each{|e|
          @config[e.downcase.intern] = klass.const_get(e)
        }
      }
      
      @config[:setting_name] ||= File.basename(@manager.rc).sub(/\.?rc$/, '')

      if $NDK_Debug
        @config[:loglevel] = 3
      end
      
      make_default_logwriter
      @logger = NDK_Logger.new(@manager, self)
      @logger.slog "load config: #{rcfile}"

      server_setting
      channel_setting
      acl_setting
      load_bots
    end

    def ch_config ch, key
      channel_info[ch] && channel_info[ch][key]
    end
    
    def canonical_channel_name ch
      ch = ch.sub(/^\!.{5}/, '!')
      identical_channel_name ch
    end

    def identical_channel_name ch
      # use 4 gsub() because of the compatibility of RFC2813(3.2)
      ch.toeuc.downcase.tr('[]\\~', '{}|^').tojis
    end

    RName = {        # ('&','#','+','!')
      '#' => 'CS-',
      '&' => 'CA-',
      '+' => 'CP-',
      '!' => 'CE-',
    }
    
    def make_logfilename tmpl, rch, cn
      ch = rch.sub(/^\!.{5}/, '!')

      case @config[:filenameencoding].to_s.downcase[0]
      when ?e # EUC
        ch = ch.toeuc.downcase
      when ?s # SJIS
        ch = ch.tosjis.downcase
      when ?u # utf-8
        ch = ch.toutf8.downcase
      else    # JIS
        ch = ch.toeuc.downcase.tojis
        ch = URI.encode(ch)
      end
      

      # escape
      ch  = ch.sub(/^[\&\#\+\!]|/){|c|
        RName[c]
      }
      ch  = ch.gsub(/\*|\:/, '_').gsub(/\//, 'I')

      # format
      str = Time.now.strftime(tmpl)
      str.gsub(/\$\{setting_name\}/, setting_name).
          gsub(/\$\{channel_name\}|\{ch\}/, cn || ch)
    end

    def log_format timefmt, msgfmts, msgobj
      text = log_format_message(msgfmts, msgobj)
      
      if timefmt && !msgobj[:nostamp]
        text = "#{msgobj[:time].strftime(timefmt)} #{text}"
      end
      
      text
    end

    def log_format_message msgfmts, msgobj
      type   = msgobj[:type]
      format = msgfmts.fetch(type, @config[:default_log][:message_format][type])

      if format.kind_of? Proc
        text = format.call(params)
      elsif format
        text = format.gsub(/\{([a-z]+)\}|\{prefix\:([a-z]+)\}/){|key|
          if $2
            method = $2.intern
            if msgobj[:orig].respond_to?(:prefix)
              (msgobj[:orig].prefix || '') =~ /^(.+?)\!(.+?)@(.+)/
              case method
              when :nick
                $1
              when :user
                $2
              when :host
                $3
              else
                "!!unknown prefix attribute: #{method}!!"
              end
            end
          else
            if m = msgobj[$1.intern]
              m
            else
              "!!unknown attribute: #{$1}!!"
            end
          end
        }
      else
        text = msgobj[:orig].to_s
      end
    end

    def make_bot_instance bk, cfg
      bk = BotClasses[bk.to_s.downcase.intern] unless bk.kind_of? Class
      bot = bk.new @manager, self, cfg || {}
      @logger.slog "bot instance: #{bot.bot_state}"
      bot
    end

    def load_botfile file
      loaded = false
      
      if @config[:plugins_dir].respond_to? :each
        @config[:plugins_dir].each{|dir|
          if load_file File.expand_path("#{file}.nb", dir)
            loaded = true
            break
          end
        }
      else
        loaded = load_file File.expand_path("#{file}.nb", @config[:plugins_dir])
      end

      unless loaded
        raise "No such bot file: #{file}"
      end
    end

    def load_file file
      if FileTest.exist? file
        Nadoka.require_bot file
        true
      else
        false
      end
    end
    
    RequiredFiles       = []
    BotClasses          = {}
  end

  def self.require_bot file
    return if NDK_Config::RequiredFiles.include? file
    
    NDK_Config::RequiredFiles.push file
    begin
      ret = ::Kernel.load(file)
    rescue
      NDK_Config::RequiredFiles.pop
      raise
    end
    ret
  end
end

module NadokaBot
  # empty module for bot namespace
  # this module is reloadable
  def self.included mod
    Nadoka::NDK_Config::BotClasses['::' + mod.name.downcase] = mod
  end
end

if $0 == __FILE__
  require 'pp'
  pp Nadoka::NDK_Config.new(nil, ARGV.shift)
end

