# -*- encoding: utf-8 -*-
$LOAD_PATH.unshift File.dirname(__FILE__)
require 'ndk/version'

Gem::Specification.new do |s|
  s.name        = "nadoka"
  s.version     = Nadoka::VERSION
  s.authors     = ["Kazuhiro NISHIYAMA", "SASADA Koichi"]
  s.email       = ["kzhr.nsym\@gmail.com"]
  s.homepage    = "https://github.com/nadoka/nadoka"
  s.summary     = %q{IRC logger, monitor and proxy program ("bot")}
  s.description = %q{
 Nadoka is a tool for monitoring and logging IRC conversations and
 responding to specially formatted requests. You define and customize
 these responses in Ruby. Nadoka is conceptually similar to Madoka, an
 older proxy written in Perl.
}.tr_s(" \n", " ").strip

  s.rubyforge_project = "nadoka"

  s.files         = `git ls-files`.split("\n")
  s.test_files    = `git ls-files -- {test,spec,features}/*`.split("\n")
  s.executables   = `git ls-files -- bin/*`.split("\n").map{ |f| File.basename(f) }
  s.require_paths = ["lib"]

  # specify any dependencies here; for example:
  # s.add_development_dependency "rspec"
  # s.add_runtime_dependency "rest-client"
end
