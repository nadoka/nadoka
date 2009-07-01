=begin

= rice - Ruby Irc interfaCE

Original Credit:

  Original Id: irc.rb,v 1.9 2001/06/13 10:22:24 akira Exp

  Copyright (c) 2001 akira yamada <akira@ruby-lang.org>
  You can redistribute it and/or modify it under the same term as Ruby.

== Modified

  Modified by K.Sasada.
  $Id$
  
=end

require 'socket'
require 'thread'
require 'monitor'
begin
  require "openssl"
rescue LoadError
end


module RICE
  class Error < StandardError; end
  class InvalidMessage < Error; end
  class UnknownCommand < Error; end

=begin

== RICE::Connection

=end

  class Connection
    class Error < StandardError; end
    class Closed < Error; end

=begin

--- RICE::Connection::new

=end

    def initialize(server, port, eol = "\r\n", ssl_params = nil)
      @conn = []
      @conn.extend(MonitorMixin)
      @main_th = nil

      self.server = server
      self.port   = port
      self.eol    = eol
      self.ssl_params = ssl_params

      @read_q  = Queue.new

      @read_th  = Thread.new(@read_q, @eol) do |read_q, eol|
        read_thread(read_q, eol)
      end

      @threads = {}
      @threads.extend(MonitorMixin)

      @dispatcher = Thread.new(@read_q) do |read_q|
        loop do
          x = read_q.pop

          ths = @threads.synchronize do
            @threads.keys
          end
          ths.each do |th|
            if th.status
              @threads[th].q.push(x)
            else
              @threads.delete(th)
            end
          end
        end # loop
        
      end

      @delay = 0.3
      @prev_send_time = Time.now
    end
    attr :delay, true
    attr_reader :server, :port, :ssl_params
    
=begin

--- RICE::Connection#server=(server)

=end

    def server=(server)
      raise RuntimeError, 
        "Already connected to #{@server}:#{@port}" unless @conn.empty?
      @server = server
    end

=begin

--- RICE::Connection#port=(port)

=end

    def port=(port)
      raise RuntimeError, 
        "Already connected to #{@server}:#{@port}" unless @conn.empty?
      @port = port
    end

=begin

--- RICE::Connection#eol=(eol)

=end

    def eol=(eol)
      raise RuntimeError, 
        "Already connected to #{@server}:#{@port}" unless @conn.empty?
      @eol = eol
    end

=begin

--- RICE::Connection#ssl_params=(ssl_params)

=end

    def ssl_params=(ssl_params)
      raise RuntimeError, 
        "Already connected to #{@server}:#{@port}" unless @conn.empty?
      unless ssl_params
        @ssl_params = false
        return
      end
      raise 'openssl library not installed' unless defined?(OpenSSL)
      ssl_params = ssl_params.to_hash
      ssl_params[:verify_mode] ||= OpenSSL::SSL::VERIFY_PEER
      store = OpenSSL::X509::Store.new
      if ssl_params.key?(:ca_cert)
        ca_cert = ssl_params.delete(:ca_cert)
        if ca_cert
          # auto setting ca_path or ca_file like open-uri.rb
          if File.directory? ca_cert
            store.add_path ca_cert
          else
            store.add_file ca_cert
          end
        else
          # use ssl_params={:ca_cert=>nil} if you want to disable auto setting
          store = nil
        end
      else
        # use default of openssl
        store.set_default_paths
      end
      if store
        ssl_params[:cert_store] = store
      end
      @ssl_params = ssl_params
    end

=begin

--- RICE::Connection#start(max_retry = 3, retry_wait = 30)

=end

    def start(max_retry = 3, retry_wait = 30)
      @client_th = Thread.current # caller thread
      if alive?
        #sleep retry_wait
        return nil
      end

      @main_th = Thread.new do
        begin
          Thread.stop
        ensure
          yield(self) if block_given?
          
          @read_th.raise(Closed) if @read_th.status
          close(true)
          @client_th.raise(Closed)
        end
      end

      begin
        open_conn
      rescue SystemCallError
        max_retry -= 1
        if max_retry == 0
          @main_th.kill
          raise
        end
        sleep retry_wait
        retry
      ensure
        @main_th.join
        nil
      end

    end

    def open_conn
      @conn.synchronize do
        conn = TCPSocket.new(@server, @port)
        if ssl_params
          context = OpenSSL::SSL::SSLContext.new
          context.set_params(ssl_params)
          conn = OpenSSL::SSL::SSLSocket.new(conn, context)
          conn.sync_close = true
          conn.connect
          if context.verify_mode != OpenSSL::SSL::VERIFY_NONE
            conn.post_connection_check(@server)
          end
        end
        @conn[0] = conn
      end
      @conn[0].extend(MonitorMixin)

      @read_th.run

      ths = @threads.synchronize do
        @threads.keys
      end
      ths.each do |th|
        th.run if th.status && th.stop?
      end
    end
    private :open_conn

=begin

--- RICE::Connection#regist(raise_on_close, *args) {...}

=end

    USER_THREAD = Struct.new('User_Thread', :q, :raise_on_close)
    def regist(raise_on_close = false, *args)
      read_q = Queue.new
      th = Thread.new(read_q, self, *args) do |read_q, conn, *args|
        yield(read_q, conn, *args)
      end
      @threads.synchronize do
        @threads[th] = USER_THREAD.new(read_q, raise_on_close)
      end
      th
    end

=begin

--- RICE::Connection#unregist(thread)

=end

    def unregist(thread)
      th = nil
      @threads.synchronize do
        th = @threads.delete(th)
      end
      th.exit
      th
    end

    def read_thread(read_q, eol)
      begin
        read_q.clear
        Thread.stop

        begin
          conn = @conn[0]
          while l = conn.gets(eol)
            begin
              read_q.push(Message.parse(l))
            rescue UnknownCommand
              $stderr.print l.inspect if $DEBUG
            rescue InvalidMessage
              begin
                read_q.push(Message.parse(l.sub(/\s*#{eol}\z/o, eol)))
              rescue
                $stderr.print l.inspect if $DEBUG
              end
            end
          end
          
        rescue IOError#, SystemCallError
          $stderr.print "#{self.inspect}: read_th get error #{$!}" if $DEBUG
          
        ensure
          raise Closed
        end
        
      rescue Closed
        begin
          @main_th.run if @main_th.alive?
        rescue Closed
        end
        retry
      end
    end
    private :read_thread

=begin

--- RICE::Connection#close(restart = false)

=end

    def close(restart = false)
      begin
        unless restart
          @main_th.exit if @main_th.alive?
          @read_th.exit if @read_th.alive?
        end
        
        conn = nil
        @conn.synchronize do
          conn = @conn.shift
        end
        conn.close if conn

        @threads.synchronize do
          @threads.each_key do |th|
            if restart
              if @threads[th].raise_on_close
                if @threads[th].raise_on_close.kind_of?(Exception)
                  th.raise(@threads[th].raise_on_close) 
                else
                  th.raise(Closed) 
                end
              end

            else
              th.exit
            end
          end
        end

      end
    end

=begin

--- RICE::Connection#alive?

=end

    def alive?
      @main_th && @main_th.alive?
    end

=begin

--- RICE::Connection#push(message)

=end

    def push(message)
      conn = @conn[0]
      if conn
        conn.synchronize do
          cmd = message.command
          if cmd == 'PRIVMSG' || cmd == 'NOTICE'
            # flood control
            t = Time.now
            if t.to_i <= @prev_send_time.to_i + 2
              sleep 1
            end
            @prev_send_time = t
          end
          conn.print message.to_s unless conn.closed?
        end
      else
        nil
      end
    end
    alias << push
  end # Connection

=begin

== RICE::Message

=end

  class Message
    module PATTERN
      # letter     =  %x41-5A / %x61-7A       ; A-Z / a-z
      # digit      =  %x30-39                 ; 0-9
      # hexdigit   =  digit / "A" / "B" / "C" / "D" / "E" / "F"
      # special    =  %x5B-60 / %x7B-7D
      #                  ; "[", "]", "\", "`", "_", "^", "{", "|", "}"
      LETTER   = 'A-Za-z'
      DIGIT    = '\d'
      HEXDIGIT = "#{DIGIT}A-Fa-f"
      SPECIAL  = '\x5B-\x60\x7B-\x7D'

      # shortname  =  ( letter / digit ) *( letter / digit / "-" )
      #               *( letter / digit )
      #                 ; as specified in RFC 1123 [HNAME]
      # hostname   =  shortname *( "." shortname )
      SHORTNAME = "[#{LETTER}#{DIGIT}](?:[-#{LETTER}#{DIGIT}\/]*[#{LETTER}#{DIGIT}])?"
      HOSTNAME  = "#{SHORTNAME}(?:\\.#{SHORTNAME})*\\.?"
      
      # servername =  hostname
      SERVERNAME = HOSTNAME

      # nickname   =  ( letter / special ) *8( letter / digit / special / "-" )
      NICKNAME = "[#{LETTER}#{SPECIAL}][\-#{LETTER}#{DIGIT}#{SPECIAL}]*"

      # user       =  1*( %x01-09 / %x0B-0C / %x0E-1F / %x21-3F / %x41-FF )
      #                 ; any octet except NUL, CR, LF, " " and "@"
      USER = '[\x01-\x09\x0B-\x0C\x0E-\x1F\x21-\x3F\x41-\xFF]+'

      # ip4addr    =  1*3digit "." 1*3digit "." 1*3digit "." 1*3digit
      IP4ADDR = "[#{DIGIT}]{1,3}(?:\\.[#{DIGIT}]{1,3}){3}"
      # ip6addr    =  1*hexdigit 7( ":" 1*hexdigit )
      # ip6addr    =/ "0:0:0:0:0:" ( "0" / "FFFF" ) ":" ip4addr
      IP6ADDR = "(?:[#{HEXDIGIT}]+(?::[#{HEXDIGIT}]+){7}|0:0:0:0:0:(?:0|FFFF):#{IP4ADDR})"
      # hostaddr   =  ip4addr / ip6addr
      HOSTADDR = "(?:#{IP4ADDR}|#{IP6ADDR})"

      # host       =  hostname / hostaddr
      HOST = "(?:#{HOSTNAME}|#{HOSTADDR})"

      # prefix     =  servername / ( nickname [ [ "!" user ] "@" host ] )
      PREFIX = "(?:#{NICKNAME}(?:(?:!#{USER})?@#{HOST})?|#{SERVERNAME})"

      # nospcrlfcl =  %x01-09 / %x0B-0C / %x0E-1F / %x21-39 / %x3B-FF
      #                 ; any octet except NUL, CR, LF, " " and ":"
      NOSPCRLFCL = '\x01-\x09\x0B-\x0C\x0E-\x1F\x21-\x39\x3B-\xFF'

      # command    =  1*letter / 3digit
      COMMAND = "(?:[#{LETTER}]+|[#{DIGIT}]{3})"

      # SPACE      =  %x20        ; space character
      # middle     =  nospcrlfcl *( ":" / nospcrlfcl )
      # trailing   =  *( ":" / " " / nospcrlfcl )
      # params     =  *14( SPACE middle ) [ SPACE ":" trailing ]
      #            =/ 14( SPACE middle ) [ SPACE [ ":" ] trailing ]
      MIDDLE = "[#{NOSPCRLFCL}][:#{NOSPCRLFCL}]*"
      TRAILING = "[: #{NOSPCRLFCL}]*"
      PARAMS = "(?:((?: +#{MIDDLE}){0,14})(?: +:(#{TRAILING}))?|((?: +#{MIDDLE}){14}):?(#{TRAILING}))"

      # crlf       =  %x0D %x0A   ; "carriage return" "linefeed"
      # message    =  [ ":" prefix SPACE ] command [ params ] crlf
      CRLF = '\x0D\x0A'
      MESSAGE = "(?::(#{PREFIX}) +)?(#{COMMAND})#{PARAMS}\s*(#{CRLF}|\n|\r)"

      CLIENT_PATTERN  = /\A#{NICKNAME}(?:(?:!#{USER})?@#{HOST})\z/on
      MESSAGE_PATTERN = /\A#{MESSAGE}\z/on
    end # PATTERN

=begin

--- RICE::Message::parse(str)

=end

    def self.parse(str)
      unless PATTERN::MESSAGE_PATTERN =~ str
        raise InvalidMessage, "Invalid message: #{str.inspect}"

      else
        prefix  = $1
        command = $2
        if $3 && $3.size > 0
          middle  = $3
          trailer = $4
        elsif $5 && $5.size > 0
          middle  = $5
          trailer = $6
        elsif $4
          params  = []
          trailer = $4
        elsif $6
          params  = []
          trailer = $6
        else
          params  = []
        end
      end
      params ||= middle.split(/ /)[1..-1]
      params << trailer if trailer

      self.build(prefix, command.upcase, params)
    end

=begin

--- RICE::Message::build(prefix, command, params)

=end

    def self.build(prefix, command, params)
      if Command::Commands.include?(command)
        Command::Commands[command].new(prefix, command, params)
      elsif Reply::Replies.include?(command)
        Reply::Replies[command].new(prefix, command, params)
      else
        raise UnknownCommand, "unknown command: #{command}"
      end
    end

=begin

--- RICE::Message#prefix

--- RICE::Message#command

--- RICE::Message#params

=end

    def initialize(prefix, command, params)
      @prefix  = prefix
      @command = command
      @params  = params
    end
    attr_accessor :prefix
    attr_reader   :command, :params

=begin

--- RICE::Message::#to_s

=end

    def to_s
      str = ''
      if @prefix
        str << ':'
        str << @prefix
        str << ' '
      end

      str << @command

      if @params
        f = false
        @params.each do |param|
          str << ' '
          if (param == @params[-1]) && (param.size == 0 || /(^:)|(\s)/ =~ param)
            str << ':'
            str << param
            f = true
          else
            str << param
          end
        end
      end

      str << "\x0D\x0A"

      str
    end

=begin

--- RICE::Message::#to_a

=end

    def to_a
      [@prefix, @command, @params]
    end

    def inspect
      sprintf('#<%s:0x%x prefix:%s command:%s params:%s>',
              self.class, self.object_id, @prefix, @command, @params.inspect)
    end

  end # Message

=begin

== RICE::Command

=end

  module Command
    class Command < Message
    end # Command

    def self.regist_command cmd
      eval <<E
      class #{cmd} < Command
      end
      Commands['#{cmd}'] = #{cmd}

      def #{cmd.downcase}(*params)
        #{cmd}.new(nil, '#{cmd}', params)
      end
      module_function :#{cmd.downcase}
E
    end
    Commands = {}
    %w(PASS NICK USER OPER MODE SERVICE QUIT SQUIT
       JOIN PART TOPIC NAMES LIST INVITE KICK
       PRIVMSG NOTICE MOTD LUSERS VERSION STATS LINKS
       TIME CONNECT TRACE ADMIN INFO SERVLIST SQUERY 
       WHO WHOIS WHOWAS KILL PING PONG ERROR
       AWAY REHASH DIE RESTART SUMMON USERS WALLOPS USERHOST ISON
    ).each do |cmd|
      self.regist_command cmd
    end
    
    class NICK
      def to_s
        str = ''
        if @prefix
          str << ':'
          str << @prefix
          str << ' '
        end

        str << @command

        str << ' '
        str << ":#{@params[0]}"

        str << "\x0D\x0A"
        str
      end
    end
    
    # XXX:
    class PRIVMSG
      def to_s
        str = ''
        if @prefix
          str << ':'
          str << @prefix
          str << ' '
        end

        str << @command

        str << ' '
        str << @params[0]

        str << ' :'
        str << @params[1..-1].join(' ')

        str << "\x0D\x0A"
        str
      end
    end
    
  end # Command

=begin

== RICE::Reply

== RICE::CommandResponse

== RICE::ErrorReply

=end

  module Reply
    class Reply < Message
    end

    class CommandResponse < Reply
    end

    class ErrorReply < Reply
    end

    Replies = {}
    Replies_num_to_name = {}
    
    %w(001,RPL_WELCOME
       002,RPL_YOURHOST
       003,RPL_CREATED
       004,RPL_MYINFO
       005,RPL_BOUNCE
       302,RPL_USERHOST 303,RPL_ISON 301,RPL_AWAY
       305,RPL_UNAWAY 306,RPL_NOWAWAY 311,RPL_WHOISUSER
       312,RPL_WHOISSERVER 313,RPL_WHOISOPERATOR
       317,RPL_WHOISIDLE 318,RPL_ENDOFWHOIS
       319,RPL_WHOISCHANNELS 314,RPL_WHOWASUSER
       369,RPL_ENDOFWHOWAS 321,RPL_LISTSTART
       322,RPL_LIST 323,RPL_LISTEND 325,RPL_UNIQOPIS
       324,RPL_CHANNELMODEIS 331,RPL_NOTOPIC
       332,RPL_TOPIC 341,RPL_INVITING 342,RPL_SUMMONING
       346,RPL_INVITELIST 347,RPL_ENDOFINVITELIST
       348,RPL_EXCEPTLIST 349,RPL_ENDOFEXCEPTLIST
       351,RPL_VERSION 352,RPL_WHOREPLY 315,RPL_ENDOFWHO
       353,RPL_NAMREPLY 366,RPL_ENDOFNAMES 364,RPL_LINKS
       365,RPL_ENDOFLINKS 367,RPL_BANLIST 368,RPL_ENDOFBANLIST
       371,RPL_INFO 374,RPL_ENDOFINFO 375,RPL_MOTDSTART
       372,RPL_MOTD 376,RPL_ENDOFMOTD 381,RPL_YOUREOPER
       382,RPL_REHASHING 383,RPL_YOURESERVICE 391,RPL_TIM
       392,RPL_ 393,RPL_USERS 394,RPL_ENDOFUSERS 395,RPL_NOUSERS
       200,RPL_TRACELINK 201,RPL_TRACECONNECTING 
       202,RPL_TRACEHANDSHAKE 203,RPL_TRACEUNKNOWN
       204,RPL_TRACEOPERATOR 205,RPL_TRACEUSER 206,RPL_TRACESERVER
       207,RPL_TRACESERVICE 208,RPL_TRACENEWTYPE 209,RPL_TRACECLASS
       210,RPL_TRACERECONNECT 261,RPL_TRACELOG 262,RPL_TRACEEND
       211,RPL_STATSLINKINFO 212,RPL_STATSCOMMANDS 219,RPL_ENDOFSTATS
       242,RPL_STATSUPTIME 243,RPL_STATSOLINE 221,RPL_UMODEIS
       234,RPL_SERVLIST 235,RPL_SERVLISTEND 251,RPL_LUSERCLIENT
       252,RPL_LUSEROP 253,RPL_LUSERUNKNOWN 254,RPL_LUSERCHANNELS
       255,RPL_LUSERME 256,RPL_ADMINME 257,RPL_ADMINLOC1
       258,RPL_ADMINLOC2 259,RPL_ADMINEMAIL 263,RPL_TRYAGAIN
       401,ERR_NOSUCHNICK 402,ERR_NOSUCHSERVER 403,ERR_NOSUCHCHANNEL
       404,ERR_CANNOTSENDTOCHAN 405,ERR_TOOMANYCHANNELS
       406,ERR_WASNOSUCHNICK 407,ERR_TOOMANYTARGETS
       408,ERR_NOSUCHSERVICE 409,ERR_NOORIGIN 411,ERR_NORECIPIENT
       412,ERR_NOTEXTTOSEND 413,ERR_NOTOPLEVEL 414,ERR_WILDTOPLEVEL
       415,ERR_BADMASK 421,ERR_UNKNOWNCOMMAND 422,ERR_NOMOTD
       423,ERR_NOADMININFO 424,ERR_FILEERROR 431,ERR_NONICKNAMEGIVEN
       432,ERR_ERRONEUSNICKNAME 433,ERR_NICKNAMEINUSE
       436,ERR_NICKCOLLISION 437,ERR_UNAVAILRESOURCE
       441,ERR_USERNOTINCHANNEL 442,ERR_NOTONCHANNEL
       443,ERR_USERONCHANNEL 444,ERR_NOLOGIN 445,ERR_SUMMONDISABLED
       446,ERR_USERSDISABLED 451,ERR_NOTREGISTERED
       461,ERR_NEEDMOREPARAMS 462,ERR_ALREADYREGISTRED
       463,ERR_NOPERMFORHOST 464,ERR_PASSWDMISMATCH
       465,ERR_YOUREBANNEDCREEP 466,ERR_YOUWILLBEBANNED
       467,ERR_KEYSE 471,ERR_CHANNELISFULL 472,ERR_UNKNOWNMODE
       473,ERR_INVITEONLYCHAN 474,ERR_BANNEDFROMCHAN 
       475,ERR_BADCHANNELKEY 476,ERR_BADCHANMASK 477,ERR_NOCHANMODES
       478,ERR_BANLISTFULL 481,ERR_NOPRIVILEGES 482,ERR_CHANOPRIVSNEEDED
       483,ERR_CANTKILLSERVER 484,ERR_RESTRICTED 
       485,ERR_UNIQOPPRIVSNEEDED 491,ERR_NOOPERHOST
       501,ERR_UMODEUNKNOWNFLAG 502,ERR_USERSDONTMATCH
       231,RPL_SERVICEINFO 232,RPL_ENDOFSERVICES
       233,RPL_SERVICE 300,RPL_NONE 316,RPL_WHOISCHANOP
       361,RPL_KILLDONE 362,RPL_CLOSING 363,RPL_CLOSEEND 
       373,RPL_INFOSTART 384,RPL_MYPORTIS 213,RPL_STATSCLINE
       214,RPL_STATSNLINE 215,RPL_STATSILINE 216,RPL_STATSKLINE
       217,RPL_STATSQLINE 218,RPL_STATSYLINE 240,RPL_STATSVLINE
       241,RPL_STATSLLINE 244,RPL_STATSHLINE 244,RPL_STATSSLINE
       246,RPL_STATSPING 247,RPL_STATSBLINE 250,RPL_STATSDLINE
       492,ERR_NOSERVICEHOST
    ).each do |num_cmd|
      num, cmd = num_cmd.split(',', 2)
      eval <<E
      class #{cmd} < #{if num[0] == ?0 || num[0] == ?2 || num[0] == ?3
                        'CommandResponse'
                       elsif num[0] == ?4 || num[0] == ?5
                        'ErrorReply'
                       end}
      end
      Replies['#{num}'] = #{cmd}
      Replies_num_to_name['#{num}'] = '#{cmd.downcase}'
      
      def #{cmd.downcase}(*params)
        #{cmd}.new(nil, '#{num}', params)
      end
      module_function :#{cmd.downcase}
E
    end
    
  end # Reply
end # RICE

