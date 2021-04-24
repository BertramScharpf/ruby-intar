#
#  intar.rb  --  Interactive Ruby evaluation
#

require "supplement"
require "supplement/terminal"
require "intar/version"
require "intar/prompt"
require "intar/redirect"


=begin rdoc

This could be opened not only by the Intar executable but also
everywhere inside your Ruby program.

= Example 1

  require "intar"
  Intar.run


= Example 2

  require "intar"
  a = "hello"
  Intar.run a, prompt: "str(%(length)i):%03n%> "


= Example 3

  require "intar"
  Intar.open show: 3, histfile: ".intar_history-example" do |i|
    i.execute "puts inspect"
    i.run
  end


=end


class Object
  def intar_binding
    binding
  end
end


class Intar

  class <<self

    def open obj = nil, **params
      i = new obj, **params
      yield i
    end

    def run obj = nil, **params
      open obj, **params do |i| i.run end
    end

  end


  DEFAULTS = {
    prompt:     "%(32)c%i%c:%1c%03n%c%> ",
    color:      true,
    show:       1,
    shownil:    false,
    pager:      nil,
    catch_exit: false,
    histhid:    true,
    histfile:   nil,
    histmax:    500,
  }

  def initialize obj = nil, **params
    @obj = obj.nil? ? (eval "self", TOPLEVEL_BINDING) : obj
    @params = DEFAULTS.dup.update params
    @binding = @obj.intar_binding
    @n = 0
    @prompt = Prompt.new
  end


  class Quit   < Exception ; end
  class Failed < Exception ; end

  def run
    prompt_load_history
    oldset = eval OLDSET, @binding
    while l = readline do
      begin
        @redir = find_redirect l
        r = if l =~ /\A\\(\w+|.)\s*(.*?)\s*\Z/ then
          m = get_metacommand $1
          send m.method, (eval_param $2)
        else
          begin
            @redir.redirect_output do eval l, @binding, @file end
          rescue SyntaxError
            raise if l.end_with? $/
            @previous = l
            next
          end
        end
      rescue Quit
        break
      rescue Failed
        switchcolor 31, 1
        puts $!
        switchcolor
        r = $!
      rescue Exception
        break if SystemExit === $! and not @params[ :catch_exit]
        show_exception
        r = $!
      else
        display r
      end
      oldset.call r, @n
    end
    prompt_save_history
  end

  def execute code
    eval code, @binding, "#{self.class}/execute"
  end


  private

  def find_redirect line
    RedirectPipe.detect line, @params[ :pager]  or
    RedirectFile.detect line, @params[ :output] or
    RedirectNone.new
  end


  OLDSET = <<~EOT
    _, __, ___ = nil, nil, nil
    proc { |r,n|
      Array === __ or __ = []
      Hash === ___ or ___ = {}
      unless r.nil? or r.equal? __ or r.equal? ___ then
        _ = r
        __.unshift r
        ___[ n] = r
      end
    }
  EOT

  autoload :Etc,    "etc"
  autoload :Socket, "socket"

  def cur_prompt prev
    p = @params[ :prompt].to_s
    p.gsub /%(?:
               \(([^\)]+)?\)
             |
               ([+-]?[0-9]+(?:\.[0-9]+)?)
             )?(.)/nx do
      case $3
        when "s" then @obj.to_s
        when "i" then $1 ? (@obj.send $1) : @obj.inspect
        when "n" then "%#$2d" % @n
        when "t" then Time.now.strftime $1||"%X"
        when "u" then Etc.getpwuid.name
        when "h" then Socket.gethostname
        when "w" then cwd_short
        when "W" then File.basename cwd_short
        when "c" then color *($1 || $2 || "").split.map { |x| x.to_i }
        when ">" then prev ? "." : Process.uid == 0 ? "#" : ">"
        when "%" then $3
        else          $&
      end
    end
  end

  def color *c
    if @params[ :color] then
      s = c.map { |i| "%d" % i }.join ";"
      "\e[#{s}m"
    end
  end

  def switchcolor *c
    s = color *c
    print s
  end

  def cwd_short
    r = Dir.pwd
    h = Etc.getpwuid.dir
    r[ 0, h.length] == h and r[ 0, h.length] = "~"
    r
  end

  def readline
    r, @previous = @previous, nil
    r or @n += 1
    begin
      cp = cur_prompt r
      l = @prompt.ask cp
      return if l.nil?
      @prompt.push l unless !r and @params[ :histhid] and l =~ /\A[ \t]+/
      if r then
        r << $/ << l
      else
        r = l unless l.empty?
      end
      cp.strip!
      cp.gsub! /\e\[[0-9]*(;[0-9]*)*m/, ""
      @file = "#{self.class}/#{cp}"
    end until r
    switchcolor
    r
  end

  # :stopdoc:
  ARROW    = "=> "
  ELLIPSIS = "..."
  # :startdoc:

  def display r
    return if r.nil? and not @params[ :shownil]
    s = @params[ :show]
    s or return
    s = s.to_i rescue 0
    i = ARROW.dup
    i << r.inspect
    if s > 0 then
      siz, = $stdout.wingeom
      siz *= s
      if i.length > siz then
        i.cut! siz-ELLIPSIS.length
        i << ELLIPSIS
      end
    end
    puts i
  end

  def show_exception
    unless $!.to_s.empty? then
      switchcolor 31, 1
      print $!
      print " " unless $!.to_s =~ /\s\z/
    end
    switchcolor 31, 22
    puts "(#{$!.class})"
    switchcolor 33
    $@.each { |b|
      r = b.starts_with? __FILE__
      break if r and (b.rest r) =~ /\A:\d+:/
      puts b
    }
    switchcolor
  end

  def eval_param l
    eot = "EOT0001"
    eot.succ! while l[ eot]
    l = eval "<<#{eot}\n#{l}\n#{eot}", @binding, @file
    l.strip!
    l.notempty?
  end

  def prompt_load_history
    @prompt.load_history @params[ :histfile]
  end
  def prompt_save_history
    @prompt.save_history @params[ :histfile], @params[ :histmax]
  end
  def prompt_scan_history
    @prompt.scan_history do |l|
      next if l =~ /\A\\/
      yield l
    end
  end



  Metacmds = Struct[ :method, :summary, :description]
  @metacmds = {}
  class <<self
    attr_reader :metacmds
    private
    def method_added sym
      if @mcd then
        names, summary, desc = *@mcd
        m = Metacmds[ sym, summary, desc]
        names.each { |n|
          @metacmds[ n] = m
        }
        @mcd = nil
      end
    end
    def metacmd names, summary, desc
      @mcd = [ names, summary, desc]
    end
  end

  def get_metacommand name
    self.class.metacmds[ name] or raise Failed, "Unknown Metacommand: #{name}"
  end

  metacmd %w(? h help), "Help for metacommands", <<~EOT
    List of Metacommands or help on a specific command, if given.
  EOT
  def cmd_help x
    @redir.redirect_output do
      if x then
        mc = get_metacommand x
        names = cmds_list[ mc]
        puts "Metacommand: #{names.join ' '}"
        puts "Summary:     #{mc.summary}"
        puts "Description:"
        puts mc.description
      else
        l = cmds_list.map { |k,v| [v,k] }
        puts "Metacommands:"
        l.each { |names,mc|
          puts "  %-20s  %s" % [ (names.join " "), mc.summary]
        }
      end
    end
    nil
  end
  def cmds_list
    l = Hash.new { |h,k| h[k] = [] }
    self.class.metacmds.each_pair { |k,v|
      l[ v].push k
    }
    l
  end

  metacmd %w(v version), "Version information", <<~EOT
    Print version number.
  EOT
  def cmd_version x
    @redir.redirect_output do
      puts "#{self.class} #{VERSION}"
      VERSION
    end
  end

  metacmd %w(q x quit exit), "Quit Intar", <<~EOT
    Leave Intar.
  EOT
  def cmd_quit x
    raise Quit
  end

  metacmd %w(cd), "Change directory", <<~EOT
    Switch to a different working directory.
    Former directories will be kept in a stack.

      %[N]    exchange with stack item #N
      =[N]    drop and set to stack item #N
      -[N]    drop stack item #N

    Default N is 1.
  EOT
  def cmd_cd x
    @wds ||= []
    y = Dir.getwd
    if x =~ /\A([%=-])?(\d+)?\z/ then
      x = $2 ? (@wds.delete_at -$2.to_i) : @wds.pop
      x or raise Failed, ($2 ? "No directory ##$2." : "No last directory.")
      case $1
        when "-" then x = nil
        when "=" then y = nil
      end
    end
    if x then
      x = File.expand_path x
      Dir.chdir x rescue raise Failed, $!.to_s
      @wds.push y if y
      y = Dir.getwd
      @wds.delete y
    end
    @redir.redirect_output do
      i = @wds.length
      @wds.each { |d|
        puts "%2d  %s" % [ i, d]
        i -= 1
      }
    end
    y
  end

  metacmd %w($ env), "Set environment variable", <<~EOT
    Set or display an environment variable.
  EOT
  def cmd_env x
    if x then
      cmds_split_assign x do |n,v|
        if v then
          v =~ /\A"((?:[^\\"]|\\.)*)"\z/ and v = ($1.gsub /\\(.)/, "\\1")
          ENV[ n] = v
        else
          ENV[ n]
        end
      end
    else
      @redir.redirect_output do
        ENV.keys.sort.each { |n|
          puts "#{n}=#{ENV[ n]}"
        }
        nil
      end
    end
  end
  def cmds_split_assign x
    n, v = x.split /\s*=\s*|\s+/, 2
    yield n, v.notempty?
  end

  metacmd %w(! sh shell), "Run shell command", <<~EOT
    Run a shell command or a subshell.
  EOT
  def cmd_shell x
    @redir.redirect_output do
      system x||ENV[ "SHELL"]||"/bin/sh" or
        raise Failed, "Exit code: #{$?.exitstatus}"
    end
    nil
  end

  metacmd %w(p param), "Set parameter", <<~EOT
    Set or display a parameter
  EOT
  def cmd_param x
    if x then
      cmds_split_assign x do |n,v|
        if v then
          @params[ n.to_sym] = parse_param v
        else
          @params[ n.to_sym]
        end
      end
    else
      @redir.redirect_output do
        @params.keys.sort.each { |n|
          puts "#{n}=#{@params[n].inspect}"
        }
        nil
      end
    end
  end
  def parse_param v
    case v
      when /\At(?:rue)?\z/i,  /\Ayes\z/i, /\Aon\z/i  then true
      when /\Af(?:alse)?\z/i, /\Ano\z/i,  /\Aoff\z/i then false
      when /\A(?:nil|none|-)\z/i                     then nil
      when /\A(?:[+-])?\d+\z/i                       then $&.to_i
      when /\A"((?:[^\\"]|\\.)*)"\z/                 then $1.gsub /\\(.)/, "\\1"
      else                                                v
    end
  end

  metacmd %w(< i input), "Load Ruby file", <<~EOT
    Load a Ruby file and eval its contents.
  EOT
  def cmd_input x
    x or raise Failed, "No input file given."
    l = File.read x rescue raise Failed, $!.to_s
    @redir.redirect_output do
      eval l, @binding, x
    end
  end

  metacmd %w(> o output), "Output to file", <<~EOT
    Append output to a file.
  EOT
  def cmd_output x
    if x then
      File.open x, "w" do end rescue raise Failed, "File error: #$!"
    end
    @params[ :output] = x
  end

  metacmd %w(e edit), "Edit last command", <<~EOT
    Take last command line from the history and open it in an editor.
    Then execute the edited line.
  EOT
  def cmd_edit x
    fn = tempname
    x = Regexp.new x if x
    p = prompt_scan_history { |l| break l if not x or l =~ x }
    File.open fn, "w" do |f| f.write p end
    begin
      system ENV[ "EDITOR"]||ENV[ "VISUAL"]||"vi", fn or
        raise Failed, "Executing editor failed: #{$?.exitstatus}"
      p = File.read fn
      p.strip!
      @prompt.push p
      @redir.redirect_output do eval p, @binding, @file end
    ensure
      File.unlink fn
    end
  end
  def tempname
    t = Time.now.strftime "%Y%m%d-%H%M%S"
    File.expand_path "intar-#{t}-#$$.rb", ENV[ "TMPDR"]||"/tmp"
  end

  metacmd %w(^ hist history), "Manage history", <<~EOT
    l load     Load history
    s save     Save history
    /          Search in history
    [N [M]]    Show last N items (skip M)
  EOT
  def cmd_history x
    case x
      when "l", "load" then prompt_load_history
      when "s", "save" then prompt_save_history
      when %r(\A(\d+)?/\s*)              then search_history $1, $'
      when %r(\A(\d+)(?:\s+(\d+))?\s*\z) then show_history $1.to_i, $2.to_i
      when nil                           then show_history 5, 0
      else                  raise Failed, "Unknown history command: #{x}"
    end
  end
  def search_history num, pat
    r = Regexp.new pat
    num ||= 1
    num = num.to_i.nonzero?
    extract_from_history { |l|
      if l =~ r then
        if num then
          break unless num > 0
          num -= 1
        end
        next l
      end
    }
  end
  def show_history n, m
    i, j = 0, 0
    extract_from_history { |l|
      i += 1
      if i > m then
        j += 1
        break if j > n
        next l
      end
    }
  end
  def extract_from_history
    a = []
    prompt_scan_history do |l|
      n = yield l
      a.push n if n
    end
  ensure
    @redir.redirect_output do
      while (p = a.pop) do
        puts p
      end
    end
  end

end

