#
#  intar.gemspec  --  Intar Gem specification
#

require "./lib/intar/version"

Gem::Specification.new do |s|
  s.name              = "intar"
  s.version           = Intar::VERSION
  s.summary           = "Interactive Ruby"
  s.description       = <<~EOT
    This is a lean replacement for Irb.
  EOT
  s.license           = "BSD-2-Clause"
  s.authors           = [ "Bertram Scharpf"]
  s.email             = "<software@bertram-scharpf.de>"
  s.homepage          = "http://www.bertram-scharpf.de"

  s.requirements      = "Ruby and some small Gems; Readline"
  s.add_dependency      "appl", "~>1"
  s.add_dependency      "supplement", "~>2"

  s.extensions        = %w()
  s.files             = %w(
                          README
                          LICENSE
                          lib/intar.rb
                          lib/intar/version.rb
                          lib/intar/prompt.rb
                          lib/intar/redirect.rb
                        )
  s.executables       = %w(
                          intar
                        )
end

