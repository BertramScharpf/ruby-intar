#
#  intar/foreign/supplement/socket.rb  --  Addition usefull Ruby socket functions
#

# The purpose of this is simply to reduce dependencies.

begin
  require "supplement/terminal"
rescue LoadError
  require "io/console"
  class IO
    def wingeom ; winsize.reverse ; end
  end
end

