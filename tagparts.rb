# -*-ruby-*-
#
# Copyright (c) 2004 SASADA Koichi <ko1 at atdot.net>
#
# This program is free software with ABSOLUTELY NO WARRANTY.
# You can re-distribute and/or modify this program under
# the same terms of the Ruby's lisence.
#
#
# $Id:$
#

require 'cgi'
module TagParts
  class TagItem
    def initialize tag, body
      @tag  = tag.to_s.downcase
      @attr = {}
      @body = []
      body.each{|e|
        add! e
      }
    end

    def make_attr_str
      @attr.map{|k,v|
        " #{CGI.escapeHTML(k.to_s).downcase}='#{CGI.escapeHTML(v)}'"
      }.join
    end
    
    def to_s
      body = @body.flatten.map{|e|
        if e.kind_of? String
          CGI.escapeHTML(e.to_s)
        else
          e.to_s
        end
      }
      "<#{@tag}#{make_attr_str}\n>#{body}</#{@tag}>\n"
    end

    def inspect
      "<TagItem: <#{@tag}#{make_attr_str}>>"
    end
    
    def add!(elem)
      if elem.kind_of? Hash
        @attr.update elem
      else
        @body << elem
      end
    end

    def [](k)
      @attr[k]
    end

    def []=(k, v)
      @attr[k] = v
    end

    def each
      @body.each{|e|
        yield e
      }
    end

    def each_leaf
      @body.each{|e|
        if e.kind_of? TagItem
          e.each_leaf(&Proc.new)
        else
          yield e
        end
      }
    end

    def each_node
      yield(self)
      @body.each{|e|
        if e.kind_of? TagItem
          e.each_node(&Proc.new)
        else
          yield e
        end
      }
    end
    
    alias << add!
  end

  @@method_prefix = '_'

  def self.newtag sym, klass = TagParts
    klass.module_eval <<-EOS
    def #{@@method_prefix}#{sym}(*args)
      TagItem.new(:#{sym}, args)
    end
    EOS
  end

  def method_missing m, *args
    if make_unknown_tag? && (/^#{@@method_prefix}(.+)/ =~ m.to_s)
      TagItem.new($1, args)
    else
      super
    end
  end

  def make_unknown_tag?
    true
  end

end

module HTMLParts
  include TagParts

  def make_unknown_tag?
    false
  end

  # copy from cgi.rb
  PARTS_1 = %w{
    TT I B BIG SMALL EM STRONG DFN CODE SAMP KBD
    VAR CITE ABBR ACRONYM SUB SUP SPAN BDO ADDRESS DIV MAP OBJECT
    H1 H2 H3 H4 H5 H6 PRE Q INS DEL DL OL UL LABEL SELECT OPTGROUP
    FIELDSET LEGEND BUTTON TABLE TITLE STYLE SCRIPT NOSCRIPT
    TEXTAREA FORM A BLOCKQUOTE CAPTION
  }
  PARTS_2 = %w{
    IMG BASE BR AREA LINK PARAM HR INPUT COL META
  }
  PARTS_3 = %w{
    HTML BODY P DT DD LI OPTION THEAD TFOOT TBODY COLGROUP TR TH TD HEAD
  }
  (PARTS_1 + PARTS_2 + PARTS_3).each{|e|
    elem = e.downcase
    TagParts.newtag elem
  }
end


__END__
include HTMLParts
puts _html(
  _head(
    _title('hogehoge')),
    _body(
      _h1('huga-'),
      _p('hogehoge', _a('hogehoge', 'href' => 'dokka'), 'huga'),
      _p('hogehoge', 'huga', ['ho-', 'hu'])
    )).to_s
