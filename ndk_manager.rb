#
# Copyright (c) 2004 SASADA Koichi <ko1 at atdot.net>
#
# This program is free software with ABSOLUTELY NO WARRANTY.
# You can re-distribute and/or modify this program under
# the same terms of the Ruby's lisence.
#
#
# $Id$
# Create : K.S. 04/04/17 17:00:44
#

require 'rice/irc'
require 'ndk_err'
require 'ndk_config'
require 'ndk_state'
require 'ndk_client'

module Nadoka
  Cmd = ::RICE::Command
  Rpl = ::RICE::Reply

  class NDK_Manager
    TimerIntervalSec = 60
    MAX_PONG_FAIL    = 5
    
    def initialize rc
      @rc = rc
      @clients= []
      @prev_timer = Time.now

      @state  = nil

      @state  = NDK_State.new self
      @config = reload_config
      @logger = @config.logger

      @state.logger = @logger
      @state.config = @config
      
      @server = nil
      
      @connected = false
      @exitting  = false

      @pong_recieved   = true
      @pong_fail_count = 0

      set_signal_trap
    end
    attr_reader :state, :connected
    
    def client_count
      @clients.size
    end
    
    def next_server_info
      svinfo = @config.server_list.shift
      @config.server_list.push svinfo
      [svinfo[:host], svinfo[:port], svinfo[:pass]]
    end
    
    def reload_config
      @config.remove_previous_setting if defined?(@config)
      @config = NDK_Config.new(self, @rc)
    end

    def start_server_thread
      @server_thread = Thread.new{
        begin
          @server = make_server()
          @logger.slog "Server connection to #{@server.server}:#{@server.port}"
          @pong_recieved = true
          @server.start(1){|sv|
            sv << Cmd.quit(@config.quit_message) if @config.quit_message
          }
          
        rescue RICE::Connection::Closed, SystemCallError
          @connected = false
          part_from_all_channels
          @logger.slog "Connection closed by server. Trying to reconnect"
          
          sleep @config.reconnect_delay
          retry
          
        rescue NDK_ReconnectToServer
          @connected = false
          part_from_all_channels
          
          begin
            @server.close if @server
          rescue RICE::Connection::Closed, SystemCallError
          end
          
          @logger.slog "Reconnect request(no server response, or client request)"
          
          sleep @config.reconnect_delay
          retry
          
        rescue Exception => e
          ndk_error e
          @clients_thread.kill if @clients_thread && @clients_thread.alive?
        end
      }
    end
    
    def make_server
      host, port, @server_passwd = next_server_info
      server = ::RICE::Connection.new(host, port)
      server.regist{|rq, wq|
        Thread.stop
        @rq = rq
        begin
          @connected = false
          server_main_proc
        rescue Exception => e
          ndk_error e
          @server_thread.kill  if @server_thread  && @server_thread.alive?
          @clients_thread.kill if @clients_thread && @clients_thread.alive?
        ensure
          @server.close
        end
      }
      server
    end
    
    def server_main_proc
      ## login

      # send passwd
      if @server_passwd
        send_to_server Cmd.pass(@server_passwd)
      end

      # send nick
      if @config.away_nick && client_count == 0
        @state.original_nick = @config.nick
        @state.nick = @config.away_nick
      else
        @state.nick = @config.nick
      end
      send_to_server Cmd.nick(@state.nick)

      # send user info
      send_to_server Cmd.user(@config.user,
                              @config.hostname, @config.servername,
                              @config.realname)
      
      # wait welcome message
      while q = recv_from_server
        case q.command
        when '001'
          break
        when '433'
          # Nickname is already in use.
          nick = @state.nick_succ(q.params[1])
          @state.nick = nick
          send_to_server Cmd.nick(nick)
        when 'NOTICE'
          # igonore
        else
          msg = "Server login fail!(#{q})"
          @logger.slog msg
          raise msg
        end
      end
      
      # change user mode
      if @config.mode
        send_to_server Cmd.mode(@state.nick, @config.mode)
      end
      
      
      # join to default channels
      if @state.current_channels.size > 0
        # if reconnect
        @state.current_channels.keys.each{|ch|
          join_to_channel ch
        }
      else
        # default join process
        @config.default_channels.each{|ch|
          join_to_channel ch
        }
      end

      @connected = true

      ##
      if @clients.size == 0
        enter_away
      end
      
      # loop
      while q = recv_from_server
        
        case q.command
        when 'PING'
          send_to_server Cmd.pong(q.params[0])
          next
        when 'PRIVMSG'
          if ctcp_message?(q.params[1])
            ctcp_message(q)
          end
        when 'JOIN'
          @state.on_join(nick_of(q), q.params[0])
        when 'PART'
          @state.on_part(nick_of(q), q.params[0])
        when 'NICK'
          @state.on_nick(nick_of(q), q.params[0])
        when 'QUIT'
          @state.on_quit(nick_of(q), q.params[0])
        when 'TOPIC'
          @state.on_topic(nick_of(q), q.params[0], q.params[1])
        when 'MODE'
          @state.on_mode(nick_of(q), q.params[0], q.params[1..-1])
          
        when '353' # RPL_NAMREPLY
          @state.on_353(q.params[2], q.params[3])
        when '332' # RPL_TOPIC
          @state.on_332(q.params[1], q.params[2])
          
        when '433', '436', '437'
          # ERR_NICKNAMEINUSE, ERR_NICKCOLLISION, ERR_UNAVAILRESOURCE
          # change try nick
          nick = @state.nick_succ(q.params[1])
          send_to_server Cmd.nick(nick)
          @logger.slog("Retry nick setting: #{nick}")
          
        else
          # 
        end

        
        send_to_clients q
        send_to_bot q
        @logger.logging q
      end
    end

    def join_to_channel ch
      if @config.channel_info[ch] && @config.channel_info[ch][:key]
        send_to_server Cmd.join(ch, @config.channel_info[ch][:key])
      else
        send_to_server Cmd.join(ch)
      end
    end
    
    def enter_away
      return if @exitting
      
      send_to_server Cmd.away(@config.away_message) if @config.away_message

      # change nick
      if @state.nick != @config.away_nick && @config.away_nick
        @state.original_nick = @state.nick
        send_to_server Cmd.nick(@config.away_nick)
      end

      # part channel
      @config.login_channels.each{|ch|
        if @config.channel_info[ch] && @state.channels.include?(ch)
          if @config.channel_info[ch][:part_message]
            send_to_server Cmd.part(ch, @config.channel_info[ch][:part_message])
          else
            send_to_server Cmd.part(ch)
          end
        end
      }
    end

    def leave_away
      return if @exitting

      send_to_server Cmd.away()

      if @config.away_nick && @state.original_nick
        send_to_server Cmd.nick(@state.original_nick)
        @state.original_nick = nil
        sleep 2 # wait for server response
      end

      @config.login_channels.each{|ch|
        send_to_server Cmd.join(ch)
      }
    end
    
    def start_clients_thread
      @clients_thread = Thread.new{
        begin
          @cserver = TCPServer.new(@config.client_server_host,
                                   @config.client_server_port)
          @logger.slog "Open Client Server Port: #{@cserver.addr.join(' ')}"
          
          while true
            # wait for client connections
            Thread.start(@cserver.accept){|cc|
              client = nil
              begin
                if !@config.acl_object || @config.acl_object.allow_socket?(cc)
                  client = NDK_Client.new(@config, cc, self)
                  @clients << client
                  client.start
                else
                  @logger.slog "ACL denied: #{cc.peeraddr.join(' ')}"
                end
              rescue Exception => e
                ndk_error e
              ensure
                @clients.delete client
                invoke_event :enter_away, client_count
                cc.close unless cc.closed?
              end
            }
          end
        rescue Exception => e
          ndk_error e
        ensure
          @clients.each{|cl|
            cl.kill
          }
          if @cserver
            @logger.slog "Close Client Server Port: #{@cserver.addr.join(' ')}"
            @cserver.close unless @cserver.closed?
          end
          @server_thread.kill if @server_thread.alive?
        end
      }
    end
    
    def start
      start_server_thread
      start_clients_thread
      timer_thread = Thread.new{
        begin
          @pong_recieved   = true
          @pong_fail_count = 0
          while true
            slp = Time.now.to_i % TimerIntervalSec
            slp = TimerIntervalSec if slp < (TimerIntervalSec / 2)
            sleep slp
            send_to_bot :timer, Time.now

            if @connected
              if @pong_recieved
                @pong_fail_count = 0
              else
                # fail
                @pong_fail_count += 1
                @logger.dlog "PONG MISS: #{@pong_fail_count}"
                
                if @pong_fail_count > MAX_PONG_FAIL
                  @pong_fail_count = 0
                  invoke_event :reconnect_to_server
                end
              end
              
              @pong_recieved = false
              @server << Cmd.ping(@server.server)
            else
              @pong_recieved   = true
              @pong_fail_count = 0
            end
            
          end
          
        rescue Exception => e
          ndk_error e
        end
      }
      
      begin
        @server_thread.join
      rescue Interrupt
        @exitting = true
      ensure
        @server_thread.kill  if @server_thread  && @server_thread.alive?
        @clients_thread.kill if @clients_thread && @clients_thread.alive?
        timer_thread.kill if timer_thread && timer_thread.alive?
        
        @server.close if @server
      end
    end
    
    def send_to_server msg
      @logger.dlog "[>S] #{msg}"
      @server << msg
    end
    
    def recv_from_server
      while q = @rq.pop
        
        # Event
        if q.kind_of? Array
          exec_event q
          next
        end
        
        # Server -> Nadoka message
        case q.command
        when 'PING'
          @server << Cmd.pong(q.params[0])
        when 'PONG'
          @pong_recieved = true
        when 'NOTICE'
          @logger.dlog "[<S] #{q}"
          if msg = filter_message(@config.notice_filter, q)
            return q
          end
        when 'PRIVMSG'
          @logger.dlog "[<S] #{q}"
          if msg = filter_message(@config.privmsg_filter, q)
            return q
          end
        else
          @logger.dlog "[<S] #{q}"
          return q
        end
      end
    end

    def filter_message filter, msg
      return msg if filter.nil? || filter.empty?
      
      begin
        if filter.respond_to? :each
          filter.each{|fil|
            fil.call msg.dup
          }
        else
          filter.call msg.dup
        end
      rescue NDK_FilterMessage_SendCancel
        @logger.dlog "[NDK] Message Canceled"
        return false
      rescue NDK_FilterMessage_Replace => e
        @logger.dlog "[NDK] Message Replaced: #{e}"
        return e.msg
      rescue NDK_FilterMessage_OnlyBot
        @logger.dlog "[NDK] Message only bot"
        send_to_bot msg
        return false
      rescue NDK_FilterMessage_OnlyLog
        @logger.dlog "[NDK] Message only log"
        @logger.logging msg
        return false
      rescue NDK_FilterMessage_BotAndLog
        @logger.dlog "[NDK] Message log and bot"
        send_to_bot msg
        @logger.logging msg
        return false
      end
      msg
    end
    
    def invoke_event ev, *arg
      arg.unshift ev
      @rq && (@rq << arg)
    end

    def exec_event q
      # special event
      case q[0]
      when :reload_config
        # q[1] must be client object
        begin
          reload_config
          if q[1]
            q[1] << Cmd.notice(@state.nick, "configuration is reloaded")
          end
        rescue Exception => e
          if q[1]
            q[1] << Cmd.notice(@state.nick, "error is occure while reloading configuration")
            q[1] << Cmd.notice(@state.nick, e.message)
            e.backtrace.each{|line|
              q[1] << Cmd.notice(@state.nick, line)
            }
          end
        end
        
      when :quit_program
        @exitting = true
        Thread.main.raise NDK_QuitProgram
        
      when :restart_program
        @exitting = true
        Thread.main.raise NDK_RestartProgram

      when :reconnect_to_server
        @connected = false
        @server_thread.raise NDK_ReconnectToServer
        
      when :invoke_bot
        # q[1], q[2] are message and argument
        send_to_bot q[1], *q[2..-1]
        
      when :enter_away
        if q[1] == 0
          enter_away
        end
        
      when :leave_away
        if q[1] == 1
          leave_away
        end
      end
    end

    def set_signal_trap
      list = Signal.list.keys
      Signal.trap(:INT){
        # invoke_event :quit_program
        Thread.main.raise NDK_QuitProgram
      } if list.any?{|e| e == 'INT'}
      Signal.trap(:HUP){
        # reload config
        invoke_event :reload_config
      } if list.any?{|e| e == 'HUP'}
      trap(:USR1){
        # SIGUSR1
        invoke_event :invoke_bot, :sigusr1
      } if list.any?{|e| e == 'USR1' }
      trap(:USR2){
        # SIGUSR2
        invoke_event :invoke_bot, :sigusr2
      } if list.any?{|e| e == 'USR2' }
    end
    
    def about_me? msg
      qnick = Regexp.quote(@state.nick || '')
      if msg.prefix =~ /^#{qnick}!/
        true
      else
        false
      end
    end

    def own_nick_change? msg
      if msg.command == 'NICK' && msg.params[0] == @state.nick
        nick_of(msg)
      else
        false
      end
    end

    def part_from_all_channels
      @state.channels.each{|ch, cs|
        cmd = Cmd.part(ch)
        cmd.prefix = @state.nick #m
        send_to_clients cmd
      }
      @state.clear_channels_member
    end
    
    # server -> clients
    def send_to_clients msg
      if msg.command == 'PRIVMSG' && !(msg = filter_message(@config.privmsg_filter_light, msg))
        return
      end

      if(old_nick = own_nick_change?(msg))
        @clients.each{|cl|
          cl.add_prefix2(msg, old_nick)
          cl << msg
        }
      elsif about_me? msg
        @clients.each{|cl|
          cl.add_prefix(msg)
          cl << msg
        }
      else
        @clients.each{|cl|
          cl << msg
        }
      end
    end

    # clientA -> other clients
    # bot     -> clients
    def send_to_clients_otherwise msg, elt
      @clients.each{|cl|
        if cl != elt
          cl.add_prefix(msg) unless msg.prefix
          cl << msg
        end
      }
      invoke_event :invoke_bot, msg if elt
      @logger.logging msg
    end
    
    def ctcp_message? arg
      arg[0] == 1
    end
    
    def ctcp_message msg
      if /\001(.+)\001/ =~ msg.params[1]
        ctcp_cmd = $1
        case ctcp_cmd
        when 'VERSION'
          send_to_server Cmd.notice(nick_of(msg), "\001VERSION #{Nadoka.version}\001")
        when 'TIME'
          send_to_server Cmd.notice(nick_of(msg), "\001TIME #{Time.now}\001")
        else
          
        end
      end
    end
    
    def nick_of msg
      if /^([^!]+)\!?/ =~ msg.prefix.to_s
        $1
      else
        @state.nick
      end
    end

    class PrefixObject
      def initialize prefix
        parse_prefix prefix
        @prefix = prefix
      end
      attr_reader :nick, :user, :host, :prefix

      def parse_prefix prefix
        if /^(.+?)\!(.+?)@(.+)/ =~ prefix.to_s
          # command
          @nick, @user, @host = $1, $2, $3
        else
          # server reply
          @nick, @user, @host = nil, nil, prefix
        end
      end

      def to_s
        @prefix
      end
    end
    
    def make_prefix_object msg
      prefix = msg.prefix
      if prefix
        PrefixObject.new(prefix)
      else
        if /^d+$/ =~ msg.command
          PrefixObject.new(@config.nadoka_server_name)
        else
          PrefixObject.new("#{@state.nick}!#{@config.user}@#{@config.nadoka_server_name}")
        end
      end
    end
    
    # dispatch to bots
    def send_to_bot msg, *arg

      selector = 'on_' +
        if msg.respond_to? :command
          if /^\d+$/ =~ msg.command
            # reply
            prefix = make_prefix_object msg
            RICE::Reply::Replies_num_to_name[msg.command]
          else
            # command
            prefix = make_prefix_object msg
            msg.command.downcase
          end
        else
          prefix = nil
          msg.to_s
        end
      
      @config.bots.each{|bot|
        begin
          if bot.respond_to? selector
            unless prefix
              bot.__send__(selector, *arg)
            else
              bot.__send__(selector, prefix, *msg.params)
            end
          end

          if prefix && bot.respond_to?(:on_every_message)
            bot.__send__(:on_every_message, prefix, msg.command, *msg.params)
          end
          
        rescue NDK_BotBreak
          break
          
        rescue NDK_BotSendCancel
          return false
          
        rescue Exception
          ndk_error $!
        end
      }
      true
    end

    def ndk_status
      [ '== Nadoka Running Status ==',
        '- nadoka version: ' + Nadoka.version,
        '- connecting to ' + "#{@server.server}:#{@server.port}",
        '- clients status:',
          @clients.map{|e| '-- ' + e.state},
        '- Bots status:',
          @config.bots.map{|bot| '-- ' + bot.bot_state},
        '== End of Status =='
      ].flatten
    end
    
    def ndk_error err
      $stderr.puts err
      $stderr.puts err.backtrace.join("\n")
      @logger.slog err
      @logger.slog err.backtrace.join(' // ')
    end
    
  end
end


