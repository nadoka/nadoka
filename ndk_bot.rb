#
# Copyright (c) 2004 SASADA Koichi <ko1 at atdot.net>
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

    def initialize manager, config, bot_config
      @manager = manager
      @config  = config
      @logger  = config.logger
      @state   = manager.state
      @bot_config = bot_config
      
      bot_initialize
    end
    attr_accessor :raw_prefix

    # To initialize bot insntace, please overide this.
    def bot_initialize
      # do something
    end

    # This method will be called when reload configuration.
    def bot_destruct
      # do something
    end

    # To access bot confiuration, please use this.
    #
    # in configuration file, 
    # BotConfig = {
    #   :BotClassName => {
    #     ... # you can access this value
    #   }
    # }
    #
    # !! This method is obsoleted. Use @bot_config instead !!
    #
    def config
      @logger.dlog "NDK_Bot#config is obsolete. Use @bot_config instead"
      @bot_config
    end

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
    
    def on_quit prefix, ch
      
    end
    
    def on_xxx prefix, *params
      
    end
    
    In above methods, you can access nick, user, host information
    via prefix argument variable like this.

    - prefix.nick
    - prefix.user
    - prefix.host

    @raw_prefix is obsolete
    

    # This method will be called when recieved every message
    def on_every_message prefix, command, *args
      # 
    end

    
    ######
    # spcial event
    
    # It's special event that will be called about a minute.
    def on_timer timeobj
      # do something
    end

    # It's special event that will be called when new client join.
    def on_client_login client_count
      # do something
    end

    # It's special event that will be called when a client part.
    def on_client_logout client_count
      # do something
    end

    # secret api :P
    def on_client_privmsg client, ch, msg
      # do something
    end
    # secret api, too :P
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
    - @state.channel_users(ch) # channel users ['user1', ...]
    - @state.current_channels[ch].mode(nick) # nick's mode in ch

    
=end
    
    def self.inherited subklass
      BotClass << subklass
    end
    
  end
end

