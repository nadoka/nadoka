#
# Copyright (c) 2004-2005 SASADA Koichi <ko1 at atdot.net>
#
# This program is free software with ABSOLUTELY NO WARRANTY.
# You can re-distribute and/or modify this program under
# the same terms of the Ruby's lisence.
#
#
# $Id$
# Create : K.S. 04/04/17 16:50:10
#

require 'thread'

module Nadoka
  class NDK_Client
    def initialize config, sock, manager
      @sock   = sock

      @config = config
      @logger = config.logger
      @manager= manager
      @state  = manager.state

      @queue  = Queue.new
      @remote_host = @sock.peeraddr[2]
      @thread = Thread.current
      @connected = false

      # client information
      @realname = nil
      @hostname = nil
    end
    
    def start
      send_thread = Thread.new{
        begin
          while q = @queue.pop
            begin
              send_to_client q
            end
          end
        rescue Exception => e
          @manager.ndk_error e
        end
      }
      begin
        if login
          @connected = true
          begin
            @manager.invoke_event :leave_away, @manager.client_count
            @manager.invoke_event :invoke_bot, :client_login, @manager.client_count, self
            while msg = recv_from_client
              send_from_client msg, self
            end
          rescue NDK_QuitClient
            # finish
          ensure
            @manager.invoke_event :invoke_bot, :client_logout, @manager.client_count, self
          end
        end
      rescue Exception
        @manager.ndk_error $!
      ensure
        @logger.slog "Client #{@realname}@#{@remote_host} disconnected."
        @sock.close
        send_thread.kill if send_thread && send_thread.alive?
      end
    end
    
    def kill
      @thread && @thread.kill
    end
    
    def recv_from_client
      while !@sock.closed?
        begin
          str = @sock.gets
          if str
            msg = ::RICE::Message::parse str
            
            case msg.command
            when 'PING'
              send_msg Cmd.pong(*msg.params[0]), false
            when 'PONG'
              # ignore
            else
              @logger.dlog "[C>] #{str}"
              return msg
            end
          else
            break
          end
        rescue ::RICE::UnknownCommand, ::RICE::InvalidMessage
          @logger.slog "Invalid Message: #{str}"
        rescue Exception => e
          @manager.ndk_error e
          break
        end
      end
    end
    
    def push msg
      if @connected
        @queue << msg
      end
    end
    alias << push
    
    def login
      pass = nil
      nick = nil
      @username = nil
      
      while (nick == nil) || (@username == nil)
        msg = recv_from_client
        return nil if msg == nil
        
        case msg.command
        when 'USER'
          @username, @hostname, @servername, @realname = msg.params
        when 'NICK'
          nick = msg.params[0]
        when 'PASS'
          pass = msg.params[0]
        else
          raise "Illegal login sequence: #{msg}"
        end
      end
      
      if @config.client_server_pass && (@config.client_server_pass != pass)
        send_reply Rpl.err_passwdmismatch(nick, "Password Incorrect.")
        return false
      end
      
      send_reply Rpl.rpl_welcome( nick,
        'Welcome to the Internet Relay Network'+"#{nick}! #{@username}@#{@remote_host}")
      send_reply Rpl.rpl_yourhost(nick, "Your host is nadoka, running version #{NDK_Version}")
      send_reply Rpl.rpl_created( nick, 'This server was created ' + NDK_Created.asctime)
      send_reply Rpl.rpl_myinfo(  nick, "nadoka #{NDK_Version} aoOirw abeiIklmnoOpqrstv")

      send_motd(nick)
      
      send_command Cmd.nick(@state.nick), nick
      nick = @manager.state.nick

      @manager.state.current_channels.each{|ch, chs|
        send_command Cmd.join(chs.name)
        if chs.topic
          send_reply Rpl.rpl_topic(@state.nick, chs.name, chs.topic)
        else
          send_reply Rpl.rpl_notopic(@state.nick, chs.name, "No topic is set.")
        end
        send_reply Rpl.rpl_namreply(  @state.nick, chs.state, chs.name, chs.names.join(' '))
        send_reply Rpl.rpl_endofnames(@state.nick, chs.name, "End of NAMES list.")
      }

      @logger.slog "Client #{@realname}@#{@remote_host} connected."
      true
    end
    
    def send_motd nick
      send_reply Rpl.rpl_motdstart(nick, "- Nadoka Message of the Day - ")
      send_reply Rpl.rpl_motd(nick, "- Enjoy IRC chat with Nadoka chan!")
      send_reply Rpl.rpl_motd(nick, "- ")
      send_reply Rpl.rpl_endofmotd(nick, "End of MOTD command.")
    end
    
    # :who!~username@host CMD ..
    def send_command cmd, nick = @manager.state.nick
      msg = add_prefix(cmd, "#{nick}!#{@username}@#{@remote_host}")
      send_msg msg
    end

    # :serverinfo REPL ...
    def send_reply repl
      msg = add_prefix(repl, @config.nadoka_server_name)
      send_msg msg
    end

    def send_msg msg, logging=true
      @logger.dlog "[C<] #{msg}" if logging
      unless @sock.closed?
        begin
          @sock.write msg.to_s
        rescue Exception => e
          @manager.ndk_error e
        end
      end
    end
    
    def send_to_client msg
      if /^\d+/ =~ msg.command
        send_reply msg
      else
        send_msg msg
      end
    end
    
    def add_prefix cmd, prefix = "#{@manager.state.nick}!#{@username}@#{@remote_host}"
      cmd.prefix = prefix
      cmd
    end
    
    def add_prefix2 cmd, nick
      cmd.prefix = "#{nick}!#{@username}@#{@remote_host}"
      cmd
    end
    

    ::RICE::Command.regist_command('NADOKA')
    
    # client -> server handling
    def send_from_client msg, from
      until @manager.connected
        # ignore
        return
      end
      
      case msg.command
      when 'NADOKA'
        nadoka_client_command msg.params[0], msg.params[1..-1]
        return
      when 'QUIT'
        raise NDK_QuitClient
      when 'PRIVMSG', 'NOTICE'
        if /^\/nadoka/ =~ msg.params[1]
          _, cmd, *args = msg.params[1].split(/\s+/)
          nadoka_client_command cmd, args
          return
        end
        if @manager.send_to_bot(:client_privmsg, self, msg.params[0], msg.params[1])
          @manager.send_to_server msg
          @manager.send_to_clients_otherwise msg, from
        end
      else
        @manager.send_to_server msg
      end
    end

    def client_notice msg
      self << Cmd.notice(@state.nick, msg)
    end

    def state
      "client from #{@remote_host}(#{@username}, #{@hostname}, #{@servername}, #{@realname})"
    end
    
    NdkCommandDescription = {
      #
      'QUIT'    => 'quite nadoka program',
      'RESTART' => 'restart nadoka program(not relaod *.rb programs)',
      'RELOAD'  => 'reload configurations and bot programs(*.nb)',
      'RECONNECT' => 'reconnect next server',
      'STATUS'  => 'show nadoka running status',
    }
    def nadoka_client_command cmd, args
      cmd ||= ''
      case cmd.upcase
      when 'QUIT'
        @manager.invoke_event :quit_program
        client_notice 'nadoka will be quit. bye!'
      when 'RESTART'
        @manager.invoke_event :restart_program, self
        client_notice 'nadoka will be restart. see you later.'
      when 'RELOAD'
        @manager.invoke_event :reload_config, self
      when 'RECONNECT'
        @manager.invoke_event :reconnect_to_server, self
      when 'STATUS'
        @manager.ndk_status.each{|msg| client_notice msg}
      when 'HELP'
        self << Cmd.notice(@state.nick, 'available: ' + NdkCommandDescription.keys.join(', '))
        if args[1]
          self << Cmd.notice(@state.nick, "#{args[1]}: #{NdkCommandDescription[args[1].upcase]}")
        end
      else
        if @manager.send_to_bot :nadoka_command, self, cmd, *args
          self << Cmd.notice(@state.nick, 'No such command. Use /NADOKA HELP.')
        end
      end
    end
  end
end

