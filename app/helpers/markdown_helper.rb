require "rouge"

module MarkdownHelper
  GFM_OPTIONS = {
    extension: {
      strikethrough: true,
      table: true,
      autolink: true,
      tasklist: true,
      footnotes: true,
      tagfilter: true
    },
    render: {
      unsafe: true,
      hardbreaks: false
    }
  }.freeze

  def render_pull_request_markdown(text, interactive_tasks: false)
    html = Commonmarker.to_html(text.to_s, options: GFM_OPTIONS, plugins: { syntax_highlighter: nil })
    html = highlight_code_blocks(html)
    html = make_tasks_interactive(html) if interactive_tasks
    html.html_safe
  end

  private

  def highlight_code_blocks(html)
    html.gsub(%r{<pre lang="([^"]*)">\s*<code>(.*?)</code>\s*</pre>}m) do
      lang = $1
      code = CGI.unescapeHTML($2)
      highlight_with_rouge(code, lang)
    end.gsub(%r{<pre>\s*<code>(.*?)</code>\s*</pre>}m) do
      code = CGI.unescapeHTML($1)
      highlight_with_rouge(code, nil)
    end
  end

  def make_tasks_interactive(html)
    index = -1
    html.gsub(/<input type="checkbox"([^>]*)\s*\/?>/) do
      index += 1
      attrs = $1
      checked = attrs.include?("checked")
      %(<input type="checkbox" class="pf-task-checkbox" data-task-index="#{index}" data-action="task-list#toggle"#{" checked" if checked}>)
    end
  end

  def highlight_with_rouge(code, lang)
    lexer = if lang.present?
      Rouge::Lexer.find_fancy(lang, code) || Rouge::Lexers::PlainText.new
    else
      begin
        Rouge::Lexer.guess(source: code)
      rescue Rouge::Guesser::Ambiguous
        Rouge::Lexers::PlainText.new
      end
    end

    formatter = Rouge::Formatters::HTML.new
    highlighted = formatter.format(lexer.lex(code.chomp))

    %(<div class="pf-md-codeblock"><pre><code>#{highlighted}</code></pre></div>)
  end
end
