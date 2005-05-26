#
# Copyright (c) 2004-2005 SASADA Koichi <ko1 at atdot.net>
#
# This program is free software with ABSOLUTELY NO WARRANTY.
# You can re-distribute and/or modify this program under
# the same terms of the Ruby's lisence.
#
#
# $Id$
# Create : K.S. 04/04/19 00:39:48
#
#
# To make bot for nadoka, see this code.
#

module Nadoka
  class NDK_Bot
    # To initialize bot insntace, please overide this.
    def bot_initialize
      # do something
    end

    # This method will be called when reload configuration.
    def bot_destruct
      # do something
    end

    # override me
    def bot_state
      info = "#<#{self.class}: #{@bot_config.inspect}>"
      if info.length > 100
        info[0..100] + '...'
      else
        info
      end
    end

    # To access bot confiuration, please use this.
    #
    # in configuration file, 
    # BotConfig = [
    # :BotClassName1,
    # :BotClassName2,
    # {
    #   :name => :BotClassName3,
    #   :setX => X,
    #   :setY => Y,
    #   ...
    # },
    # ]
    #
    # You can access above setting via @bot_config
    #

    # Mostly, you need this method.
    def send_notice ch, msg
      msg = Cmd.notice(ch, msg)
      @manager.send_to_server  msg
      @manager.send_to_clients_otherwise msg, nil
    end

    # Usualy, you must not use this
    def send_privmsg ch, msg
      msg = Cmd.privmsg(ch, msg)
      @manager.send_to_server  msg
      @manager.send_to_clients_otherwise msg, nil
    end

    # Change user's mode as 'mode' on ch.
    def change_mode ch, mode, user
      send_msg Cmd.mode(ch, mode, user)
    end

    # Change your nick to 'nick'.
    def change_nick nick
      send_msg Cmd.nick(nick)
    end

    # Send command or reply(?) to server.
    def send_msg msg
      @manager.send_to_server msg
    end

    # ccn or canonical_channel_name
    def canonical_channel_name ch
      @config.canonical_channel_name ch
    end
    alias ccn canonical_channel_name
    
=begin
    # ...
    # def on_[IRC Command or Reply(3 digits)] prefix(nick only), param1, param2, ...
    #   
    # end
    #
    
    # like these
    def on_privmsg prefix, ch, msg
      
    end
    
    def on_join prefix, ch
      
    end
    
    def on_part prefix, ch, msg=''
      
    end
    
    def on_quit prefix, msg=''
      
    end
    
    def on_xxx prefix, *params
      
    end
    
    In above methods, you can access nick, user, host information
    via prefix argument variable like this.

    - prefix.nick
    - prefix.user
    - prefix.host

    
    ######
    # spcial event

    # This method will be called when recieved every message
    def on_every_message prefix, command, *args
      # 
    end

    # if 'nick' user quit client and part ch, this event is called.
    # !! ch is canonicarized channel name !!
    def on_quit_from_channel ch, nick, qmsg
      # do something
    end
    
    # It's special event that will be called about a minute.
    def on_timer timeobj
      # do something
    end

    # It's special event that will be called when new client join.
    def on_client_login client_count, client
      # do something
    end

    # It's special event that will be called when a client part.
    def on_client_logout client_count, client
      # do something
    end

    # undocumented
    def on_client_privmsg client, ch, msg
      # do something
    end
    # undocumented
    def on_nadoka_command client, command, *params
      # do something
    end

    # on signal 'sigusr[12]' trapped
    def on_sigusr[12] # no arguments
      # do something
    end
    
    You can access your current state on IRC server via @state.
    - @state.nick         # your current nick
    - @state.channels     # channels which you are join        ['ch1', 'ch2', ...]

    # need canonicarized channel name
    - @state.channel_users(ch) # channel users ['user1', ...]
    - @state.channel_user_mode(ch, nick)
    
=end

    Cmd = ::Nadoka::Cmd
    Rpl = ::Nadoka::Rpl

    def initialize manager, config, bot_config
      @manager    = manager
      @config     = config
      @logger     = config.logger
      @state      = manager.state
      @bot_config = bot_config
      
      bot_initialize
    end

    def config
      @bot_config
    end

    def self.inherited klass
      NDK_Config::BotClasses[klass.name.downcase.intern] = klass
    end
  end
end

