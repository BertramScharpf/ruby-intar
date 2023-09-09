#
#  intar/redirect.rb  --  Output redirection for Intar
#

require "supplement"


class Intar

  class RedirectNone
    def redirect_output
      yield
    end
  end

  class Redirect
    def redirect_output
      out = outfile
      begin
        stdin, stdout = $stdin.dup, $stdout.dup
        $stdin .reopen "/dev/null"
        $stdout.reopen out
        yield
      ensure
        $stdin .reopen stdin
        $stdout.reopen stdout
        out.close
      end
    end
  end

  class RedirectPipe < Redirect
    class <<self
      def detect line, pager
        if line.slice! /\s+\|((?:\b|\/)[^|&;{}()\[\]]*)?\z/ then
          new $1||pager
        end
      end
    end
    def initialize pager
      @pager = pager||ENV[ "PAGER"]||"more"
    end
    def outfile
      IO.popen @pager.to_s, "w"
    rescue Errno::ENOENT
      raise Failed, "Pipe error: #$!"
    end
  end

  class RedirectFile < Redirect
    class <<self
      def detect line, outfile
        if line.slice! /\s+>(>)?(\S+|"((?:[^\\"]|\\.)*)")\z/ then
          p = $3 ? ($3.gsub /\\(.)/, "\\1") : $2
          append = true if $1
          new p, append
        elsif outfile then
          new outfile.to_s, true
        end
      end
    end
    def initialize path, append
      @path, @append = path, append
    end
    def outfile
      File.open @path, (@append ? "a" : "w") rescue raise Failed, "File error: #$!"
    end
  end

end

