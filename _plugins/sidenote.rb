module Jekyll
  class RenderSideNoteTag < Liquid::Tag
    @@number = 0

    require "shellwords"

    def initialize(tag_name, text, tokens)
      super
      @@number = 0
      @text = text
    end

    def render(context)
      num = @@number = @@number + 1
      %{<span id="sn-#{num}" class="sidenote" data-sidenote-number="#{num}"><sup class="sidenote-number">#{num}</sup>&nbsp;#{@text} <a class="sidenote-back" href="#sn-ref-#{num}">↩</a></span><sup class="sidenote-number" id="sn-ref-#{num}"><a href="#sn-#{num}">#{num}</a></sup>}
    end
  end
end

Liquid::Template.register_tag('sidenote', Jekyll::RenderSideNoteTag)
