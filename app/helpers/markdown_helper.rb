require "rouge"
require "cgi"

module MarkdownHelper
  def render_pull_request_markdown(text)
    lines = text.to_s.gsub("\r\n", "\n").split("\n")
    blocks = []
    index = 0

    while index < lines.length
      line = lines[index]

      if line.strip.start_with?("```")
        blocks << render_markdown_codeblock(lines, index)
        index = @markdown_next_index
        next
      end

      if line.match?(/\A#+\s+/)
        blocks << render_markdown_heading(line)
        index += 1
        next
      end

      if list_item?(line)
        blocks << render_markdown_list(lines, index)
        index = @markdown_next_index
        next
      end

      if line.blank?
        index += 1
        next
      end

      blocks << render_markdown_paragraph(lines, index)
      index = @markdown_next_index
    end

    safe_join(blocks)
  end

  private

  def render_markdown_codeblock(lines, start_index)
    fence = lines[start_index].strip.delete_prefix("```").strip
    code_lines = []
    index = start_index + 1

    while index < lines.length && !lines[index].strip.start_with?("```")
      code_lines << lines[index]
      index += 1
    end

    @markdown_next_index = [index + 1, lines.length].min
    code = code_lines.join("\n")
    formatter = Rouge::Formatters::HTML.new
    lexer = markdown_lexer_for(fence, code)
    highlighted = formatter.format(lexer.lex(code))

    content_tag(:div, class: "pf-md-codeblock") do
      content_tag(:pre) do
        content_tag(:code, highlighted.html_safe)
      end
    end
  end

  def render_markdown_heading(line)
    match = line.match(/\A(#+)\s+(.+)\z/)
    level = match[1].length
    content_tag(:"h#{level}", render_markdown_inline(match[2]), class: "pf-md-heading")
  end

  def render_markdown_list(lines, start_index)
    items = []
    index = start_index

    while index < lines.length && list_item?(lines[index])
      items << lines[index]
      index += 1
    end

    @markdown_next_index = index

    content_tag(:ul, class: "pf-md-list") do
      safe_join(items.map { |item| render_markdown_list_item(item) })
    end
  end

  def render_markdown_list_item(line)
    match = line.match(/\A[*-]\s+\[(x| )\]\s+(.+)\z/i)

    if match
      checked = match[1].casecmp("x").zero?
      body = match[2]

      content_tag(:li, class: "pf-md-list-item pf-md-list-item--task") do
        check = tag.input(type: "checkbox", disabled: true, checked: checked, class: "pf-md-checkbox")
        safe_join([ check, content_tag(:span, render_markdown_inline(body)) ])
      end
    else
      body = line.sub(/\A[*-]\s+/, "")
      content_tag(:li, render_markdown_inline(body), class: "pf-md-list-item")
    end
  end

  def render_markdown_paragraph(lines, start_index)
    buffer = []
    index = start_index

    while index < lines.length && lines[index].present? && !lines[index].strip.start_with?("```") && !lines[index].match?(/\A#+\s+/) && !list_item?(lines[index])
      buffer << lines[index].strip
      index += 1
    end

    @markdown_next_index = index
    content_tag(:p, render_markdown_inline(buffer.join(" ")), class: "pf-md-paragraph")
  end

  def render_markdown_inline(text)
    replacements = {}
    placeholder = 0

    processed = text.to_s.gsub(/!\[([^\]]*)\]\(([^)]+)\)|\[([^\]]+)\]\(([^)]+)\)|`([^`]+)`|\*\*([^*]+)\*\*/) do
      key = "__MDTOKEN#{placeholder}__"
      placeholder += 1

      m = Regexp.last_match
      replacements[key] =
        if m[2] # Image: ![alt](url) — group 2 is the image src
          tag.img(src: m[2], alt: CGI.escapeHTML(m[1].to_s), style: "max-width: 100%")
        elsif m[4] # Link: [text](url)
          link_to(CGI.escapeHTML(m[3]), m[4], target: "_blank", rel: "noreferrer")
        elsif m[5] # Inline code: `code`
          content_tag(:code, CGI.escapeHTML(m[5]))
        else # Bold: **text**
          content_tag(:strong, CGI.escapeHTML(m[6]))
        end

      key
    end

    escaped = CGI.escapeHTML(processed)
    replacements.each { |key, html| escaped.gsub!(key, html) }
    escaped.html_safe
  end

  def markdown_lexer_for(fence, code)
    return Rouge::Lexers::PlainText.new if code.blank?

    if fence.present?
      Rouge::Lexer.find_fancy(fence, code) || Rouge::Lexers::PlainText.new
    else
      Rouge::Lexer.guess(source: code)
    end
  rescue Rouge::Guesser::Ambiguous, Rouge::Guesser::GuessError
    Rouge::Lexers::PlainText.new
  end

  def list_item?(line)
    line.match?(/\A[*-]\s+/)
  end
end
