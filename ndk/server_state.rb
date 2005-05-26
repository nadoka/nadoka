#
# Copyright (c) 2004-2005 SASADA Koichi <ko1 at atdot.net>
#
# This program is free software with ABSOLUTELY NO WARRANTY.
# You can re-distribute and/or modify this program under
# the same terms of the Ruby's lisence.
#
#
# $Id$
# Create : K.S. 04/04/20 10:42:27
#

module Nadoka
  class NDK_State
    class ChannelState
      def initialize name
        @name  = name
        @topic = nil
        @member= {}

        # member data
        # { "nick" => "mode", ... }
      end

      attr_accessor :topic
      attr_reader   :member, :name

      # get members nick array
      def members
        @member.keys
      end

      # get user's mode
      def mode nick
        @member[nick]
      end
      
      def names
        @member.map{|nick, mode|
          prefix = if /o/ =~ mode
            '@'
          elsif /v/ =~ mode
            '+'
          else
            ''
          end
          prefix + nick
        }
      end
      
      def state
        '='
      end

      def clear_members
        @member = {}
      end
      
      #####################################
      
      def on_join nick, mode=''
        @member[nick] = mode
      end
      
      def on_part nick
        @member.delete nick
      end
      
      def on_nick nick, newnick
        if @member.has_key? nick
          @member[newnick] = @member[nick]
          @member.delete nick
        end
      end
      
      def on_kick nick
        if @member.has_key? nick
          @member.delete nick
        end
      end
      
      MODE_WITH_NICK_ARG = 'ov'
      MODE_WITH_ARGS     = 'klbeI'
      MODE_WITHOUT_ARGS  = 'aimnqpsrt'
      
      def on_mode nick, args
        if @member.has_key? nick || nick == @current_nick
          while mode = args.shift
            modes = mode.split(//)
            flag  = modes.shift
            modes.each{|m|
              if MODE_WITH_NICK_ARG.include? m
                chg_mode args.shift, flag, m
              elsif MODE_WITH_ARGS.include? m
                args.shift
              elsif MODE_WITHOUT_ARGS.include? m
                # ignore
              end
            }
          end
        end
      end

      def chg_mode nick, flag, mode
        if @member.has_key? nick
          if flag == '+'
            @member[nick] += mode
          elsif flag == '-'
            @member[nick].gsub!(mode, '')
          end
        end
      end

      def to_s
        str = ''
        @member.each{|k, v|
          str << "#{k}: #{v}, "
        }
        str
      end
    end
    
    def initialize manager
      @manager = manager
      @config  = nil
      @logger  = nil
      
      @current_nick     = nil
      @original_nick    = nil
      @try_nick         = nil
      
      @current_channels = {}
    end
    attr_reader :current_channels
    attr_reader :current_nick
    attr_accessor :original_nick
    attr_writer :logger, :config
    
    def nick=(n)
      @try_nick     = nil
      @current_nick = n
    end
    
    def nick
      @current_nick
    end

    def nick_succ fail_nick
      if @try_nick
        if @try_nick.length == fail_nick
          @try_nick.succ!
        else
          @try_nick = fail_nick[0..-2] + '0'
        end
      else
        @try_nick = fail_nick + '0'
      end
    end
    
    def channels
      @current_channels.keys
    end

    # need canonicarized channel name
    def channel_users ch
      if @current_channels.has_key? ch
        @current_channels[ch].members
      else
        []
      end
    end
    
    # need canonicarized channel name
    def channel_user_mode ch, user
      if channel_users(ch).include?(user)
        @current_channels[ch].mode(user)
      else
        ''
      end
    end
    
    def canonical_channel_name ch
      @config.canonical_channel_name ch
    end

    def clear_channels_member
      @current_channels.each{|ch, cs|
        cs.clear_members
      }
    end
    
    #
    def on_join user, rch
      ch = canonical_channel_name(rch)
      
      msg = "+ #{user} to #{ch}"
      if user == nick
        @logger.clog ch, msg
        chs = @current_channels[ch] = ChannelState.new(rch)
      else
        if @current_channels.has_key? ch
          @logger.clog ch, msg
          @current_channels[ch].on_join(user)
        end
      end
      @logger.log msg
    end
    
    def on_part user, rch
      ch = canonical_channel_name(rch)

      msg = "- #{user} from #{ch}"
      if user == nick
        @logger.clog ch, msg
        @current_channels.delete ch
      else
        if @current_channels.has_key? ch
          @logger.clog ch, msg
          @current_channels[ch].on_part user
        end
      end
      @logger.log msg
    end
    
    def on_nick user, newnick
      msg = "#{user} -> #{newnick}"
      if user == nick
        @current_nick = newnick
        @try_nick     = nil
      end
      # logging
      @current_channels.each{|ch, chs|
        if chs.on_nick user, newnick
          @logger.clog ch, msg
        end
      }
      @logger.log msg
    end
    
    def on_quit user, qmsg
      if user == nick
        @current_channels = {} # clear
      else
        # logging
        @current_channels.each{|ch, chs|
          if chs.on_part(user)
            @manager.invoke_event :invoke_bot, :quit_from_channel, chs.name, user, qmsg
            @logger.clog ch, "- #{user} from #{chs.name}(#{qmsg})"
          end
        }
      end
      @logger.log "- #{user}(#{qmsg})"
    end
    
    def on_mode user, rch, args
      ch = canonical_channel_name(rch)
      @logger.log "* #{user} changed mode(#{args.join(', ')}) at #{ch}"

      if @current_channels.has_key? ch
        @logger.clog ch, "* #{user} changed mode(#{args.join(', ')})"
        @current_channels[ch].on_mode user, args
      end
    end

    def on_kick kicker, rch, user, comment
      ch = canonical_channel_name(rch)
      msg = "- #{user} kicked by #{kicker} (#{comment}) from #{ch}"

      if user == nick
        @logger.clog ch, msg
        @current_channels.delete ch
      else
        if @current_channels.has_key? ch
          @logger.clog ch, msg
          @current_channels[ch].on_kick user
        end
      end
      
      @logger.log msg
    end

    def on_topic user, rch, topic
      ch = canonical_channel_name(rch)

      if @current_channels.has_key? ch
        @logger.clog ch, "<#{ch}:#{user} TOPIC> #{topic}"
        @current_channels[ch].topic = topic
      end
      @logger.log "<#{ch} TOPIC> #{topic}"
    end
    
    def on_332 rch, topic
      ch = canonical_channel_name(rch)

      if @current_channels.has_key? ch
        @current_channels[ch].topic = topic
        @logger.clog ch, "<#{ch} TOPIC> #{topic}"
      end
      @logger.log "<#{ch} TOPIC> #{topic}"
    end
    
    # RPL_NAMREPLY
    # ex) :lalune 353 test_ndk = #nadoka :test_ndk ko1_nmdk
    # 
    def on_353 rch, users
      ch = canonical_channel_name(rch)

      if @current_channels.has_key? ch
        chs = @current_channels[ch]
        users.split(/ /).each{|e|
          /^([\@\+])?(.+)/ =~ e
          case $1
          when '@'
            mode = 'o'
          when '+'
            mode = 'v'
          else
            mode = ''
          end
          chs.on_join $2, mode
        }

        # change initial mode
        if @config.channel_info[ch] &&
           (im = @config.channel_info[ch][:initial_mode]) &&
           chs.members.size == 1
          @manager.send_to_server Cmd.mode(rch, im)
        end
      end
    end

    def safe_channel? ch
      ch[0] == ?!
    end
    
    # ERR_NOSUCHCHANNEL
    # ex) :NadokaProgram 403 simm !hoge :No such channel
    def on_403 ch
      if safe_channel?(ch) && ch[1] != ?!
        @manager.join_to_channel( "!" + ch)
      end
    end
    
  end
end

