# frozen_string_literal: true

# The MIT License (MIT)
#
# Copyright (c) 2019 Kazuhiro NISHIYAMA
#
# Permission is hereby granted, free of charge, to any person obtaining a copy
# of this software and associated documentation files (the "Software"), to deal
# in the Software without restriction, including without limitation the rights
# to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
# copies of the Software, and to permit persons to whom the Software is
# furnished to do so, subject to the following conditions:
#
# The above copyright notice and this permission notice shall be included in all
# copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
# SOFTWARE.

# see https://www.freedesktop.org/software/systemd/man/sd_notify.html
class NotifySocket
  def initialize(path=ENV['NOTIFY_SOCKET'])
    @notify_socket = nil
    return unless path
    @notify_socket = Addrinfo.unix(path, :DGRAM).connect
  end

  def []=(key, value)
    return unless @notify_socket
    @notify_socket.puts "#{key}=#{value}"
  end

  def ready!
    self['READY'] = 1
  end

  def reloading!
    self['RELOADING'] = 1
  end

  def stopping!
    self['STOPPING'] = 1
  end

  # notify_socket.status = 'Completed 66% of file system check…'
  def status=(state)
    self['STATUS'] = state
  end

  # notify_socket.errno = 2
  def errno=(error_code)
    self['ERRNO'] = error_code
  end

  # notify_socket.buserror = 'org.freedesktop.DBus.Error.TimedOut'
  def buserror=(error_code)
    self['BUSERROR'] = error_code
  end

  # notify_socket.mainpid = 4711
  def mainpid=(pid)
    self['MAINPID'] = pid
  end

  def watchdog!
    self['WATCHDOG'] = 1
  end

  # notify_socket.watchdog_usec = 20_000_000
  def watchdog_usec=(usec)
    self['WATCHDOG_USEC'] = usec
  end

  def extend_timeout_usec=(usec)
    self['EXTEND_TIMEOUT_USEC'] = usec
  end
end
