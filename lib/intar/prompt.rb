#
#  intar/prompt.rb  --  Prompt for Intar
#

require "supplement"
require "reline"


class Intar

  class Prompt

    def initialize histfile: nil, limit: nil
      @limit = limit.nonzero?
      Reline::HISTORY.clear
      @new = 0
    end

    def push text
      Reline.pre_input_hook = proc {
        Reline.insert_text text
        Reline.redisplay
      }
      nil
    end

    def ask prompt
      begin
        Reline.readline prompt
      ensure
        Reline.pre_input_hook = nil
      end
    rescue Interrupt
      puts
      retry
    rescue Exception
      puts
      raise
    end

    def last
      Reline::HISTORY[-1] unless Reline::HISTORY.empty?
    end

    def scan_history
      i = Reline::HISTORY.length
      while i > 0 do
        i -= 1
        yield Reline::HISTORY[i]
      end
    end

    def push_history item
      item.empty? and return
      last != item or return
      Reline::HISTORY.push item
      @new += 1
    end

    def load_history filepath
      with_filepath filepath do |p|
        read_file_if p do |f|
          h = []
          @new.times { h.push Reline::HISTORY.pop }
          Reline::HISTORY.clear
          f.each_line { |l|
            l.chomp!
            l.sub! "\r", "\n"
            Reline::HISTORY.push l
          }
          Reline::HISTORY.push h.pop while h.any?
        end
        nil
      end
    end

    def save_history filepath, maxsize
      with_filepath filepath do |p|
        lock_histfile p do
          old, m = [], maxsize-@new
          read_file_if p do |f|
            f.each_line { |l|
              old.size >= m and old.shift
              old.push l
            }
          end
          File.open p, "w" do |f|
            old.each { |l| f.puts l }
            i = Reline::HISTORY.length - @new
            while i < Reline::HISTORY.length do
              l = Reline::HISTORY[ i].sub "\n", "\r"
              f.puts l
              i += 1
            end
          end
        end
        nil
      end
    end

    def limit_history max
      n = Reline::HISTORY.length - max
      n.times { Reline::HISTORY.shift }
      @new > max and @new = max
      nil
    end

    private

    def with_filepath filepath
      if filepath then
        p = File.expand_path filepath, "~"
        yield p
      end
    end

    def read_file_if filepath
      if File.exist? filepath then
        File.open filepath do |f|
          yield f
        end
      end
    end

    def lock_histfile filepath
      l = "#{filepath}.lock"
      loop do
        File.open l, File::CREAT|File::EXCL do end
        break
      rescue Errno::EEXIST
        puts "Lockfile #{l} exists."
        sleep 1
      end
      yield
    ensure
      File.unlink l
    end

  end

end

