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

  def render_pull_request_markdown(text)
    html = Commonmarker.to_html(text.to_s, options: GFM_OPTIONS, plugins: { syntax_highlighter: nil })
    html = highlight_code_blocks(html)
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
