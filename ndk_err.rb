#
# Copyright (c) 2004 SASADA Koichi <ko1 at atdot.net>
#
# This program is free software with ABSOLUTELY NO WARRANTY.
# You can re-distribute and/or modify this program under
# the same terms of the Ruby's lisence.
#
# 
# $Id: ndk_err.rb,v 1.9 2004/04/28 02:27:22 ko1 Exp $
# Create : K.S. 04/04/20 23:57:17
#

module Nadoka
  
  class NDK_Error < Exception
  end
  
  class NDK_QuitClient < NDK_Error
  end

  class NDK_BotBreak < NDK_Error
  end

  class NDK_BotSendCancel < NDK_Error
  end
  
  class NDK_QuitProgram < NDK_Error
  end

  class NDK_RestartProgram < NDK_Error
  end
  

  ####
  class NDK_FilterMessage_SendCancel < NDK_Error
  end

  class NDK_FilterMessage_Replace < NDK_Error
    def initialize msg
      @msg = msg
    end
    attr_reader :msg
  end

  class NDK_FilterMessage_OnlyBot < NDK_Error
  end

  class NDK_FilterMessage_OnlyLog < NDK_Error
  end

  class NDK_FilterMessage_BotAndLog < NDK_Error
  end
  
end


