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
    include Enumerable
    def initialize tag, body, ignore_empty = false
      @tag  = tag.to_s
      @attr = {}
      @body = []
      @ignore_empty = ignore_empty
      body.each{|e|
        add! e
      }
    end
    attr_reader :body, :tag, :attr
    
    def make_attr_str
      @attr.map{|k,v|
        " #{CGI.escapeHTML(k.to_s)}='#{CGI.escapeHTML(v)}'"
      }.join
    end

    def to_s
      if @body.size > 0 || @ignore_empty
        body = @body.flatten.map{|e|
          if e.kind_of? String
            CGI.escapeHTML(e.to_s)
          else
            e.to_s
          end
        }
        "<#{@tag}#{make_attr_str}\n>#{body}</#{@tag}>\n"
      else
        "<#{@tag}#{make_attr_str} /\n>"
      end
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
      @body.flatten.each{|e|
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
  
  def ignore_empty_tag?
    false
  end

  # do nothing. please override
  def tag_encoding str
    str
  end
  
  def tree2string tag
    tag_encoding(tree2string_(tag))
  end
  
  def tree2string_ tag
    bs = tag.map{|body|
      if body.kind_of? TagItem
        tree2string_(body)
      else
        CGI.escapeHTML(body.to_s)
      end
    }
    tagname = tag.tag
    attr    = tag.make_attr_str
    if bs.size > 0 || ignore_empty_tag?
      "<#{tagname}#{attr}\n>#{bs}</#{tagname}>\n"
    else
      "<#{tagname}#{attr}\n/>"
    end
  end
  
  @@method_prefix = '_'

  def self.newtag sym, ignore_empty, klass = TagParts
    klass.module_eval <<-EOS
    def #{@@method_prefix}#{sym}(*args)
      TagItem.new(:#{sym}, args, #{ignore_empty})
    end
    EOS
  end

  TagParts.module_eval <<-EOS
    def #{@@method_prefix}(tag, *args)
      TagItem.new(tag, args, false)
    end
  EOS
  
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

  def ignore_empty_tag?
    true
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
    TagParts.newtag elem, true
  }
end

__END__

include HTMLParts
tags = _html(
  _head(
    _title('hogehoge')),
    _body(
      _br(),
      _h1('huga-'),
      _p('hogehoge', _a('hogehoge', 'href' => 'dokka'), 'huga'),
      _p('hogehoge', 'huga', ['ho-', 'hu'])
    ))

puts tags.to_s
puts tree2string(tags)
p( tags.to_s == tree2string(tags) )

