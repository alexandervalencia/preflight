require "rouge"
require "cgi"

module PullRequestsHelper
  FileViewState = Data.define(:label, :css_class, :action_label)
  SplitDiffCell = Data.define(:number, :content, :kind)
  SplitDiffRow = Data.define(:kind, :left, :right, :comment_side, :comment_line_number, :comments, :hunk)
  UnifiedDiffRow = Data.define(:kind, :left_number, :right_number, :content, :cell_kind, :comment_side, :comment_line_number, :comments, :hunk)

  def comment_target_for(line)
    return ["left", line.old_number] if line.type == :deletion
    return ["right", line.new_number] if line.new_number.present?

    [nil, nil]
  end

  def diff_line_class(line)
    "diff-line diff-line--#{line.type}"
  end

  def file_view_state(pull_request, viewed_file)
    return FileViewState.new(label: "Unviewed", css_class: "view-state--unviewed", action_label: "Mark as viewed") unless viewed_file
    return FileViewState.new(label: "Viewed", css_class: "view-state--viewed", action_label: nil) if viewed_file.current?(repository: pull_request.git_repository)

    FileViewState.new(label: "New changes", css_class: "view-state--new", action_label: "Mark as viewed again")
  end

  def pr_status_summary(comparison)
    additions = 0
    deletions = 0

    comparison.files.each do |file|
      stats = diff_stats(file)
      additions += stats[:additions]
      deletions += stats[:deletions]
    end

    { additions:, deletions: }
  end

  def diff_stats(file)
    {
      additions: file.lines.count { |line| line.type == :addition },
      deletions: file.lines.count { |line| line.type == :deletion }
    }
  end

  def split_diff_rows(file, comments_by_key)
    rows = []
    lines = file.lines
    index = 0

    while index < lines.length
      line = lines[index]

      if line.type == :hunk
        rows << SplitDiffRow.new(
          kind: :hunk,
          left: nil,
          right: nil,
          comment_side: nil,
          comment_line_number: nil,
          comments: [],
          hunk: line.content
        )
        index += 1
        next
      end

      if line.type == :deletion && lines[index + 1]&.type == :addition
        deletion = lines[index]
        addition = lines[index + 1]
        rows << build_split_row(
          left: SplitDiffCell.new(number: deletion.old_number, content: deletion.content, kind: :deletion),
          right: SplitDiffCell.new(number: addition.new_number, content: addition.content, kind: :addition),
          comment_side: "right",
          comment_line_number: addition.new_number,
          comments_by_key: comments_by_key,
          path: file.path
        )
        index += 2
        next
      end

      case line.type
      when :context
        rows << build_split_row(
          left: SplitDiffCell.new(number: line.old_number, content: line.content, kind: :context),
          right: SplitDiffCell.new(number: line.new_number, content: line.content, kind: :context),
          comment_side: "right",
          comment_line_number: line.new_number,
          comments_by_key: comments_by_key,
          path: file.path
        )
      when :deletion
        rows << build_split_row(
          left: SplitDiffCell.new(number: line.old_number, content: line.content, kind: :deletion),
          right: SplitDiffCell.new(number: nil, content: "", kind: :empty),
          comment_side: "left",
          comment_line_number: line.old_number,
          comments_by_key: comments_by_key,
          path: file.path
        )
      when :addition
        rows << build_split_row(
          left: SplitDiffCell.new(number: nil, content: "", kind: :empty),
          right: SplitDiffCell.new(number: line.new_number, content: line.content, kind: :addition),
          comment_side: "right",
          comment_line_number: line.new_number,
          comments_by_key: comments_by_key,
          path: file.path
        )
      end

      index += 1
    end

    rows
  end

  def unified_diff_rows(file, comments_by_key)
    file.lines.map do |line|
      if line.type == :hunk
        UnifiedDiffRow.new(
          kind: :hunk,
          left_number: nil,
          right_number: nil,
          content: nil,
          cell_kind: :hunk,
          comment_side: nil,
          comment_line_number: nil,
          comments: [],
          hunk: line.content
        )
      else
        comment_side, comment_line_number = comment_target_for(line)

        UnifiedDiffRow.new(
          kind: :line,
          left_number: line.old_number,
          right_number: line.new_number,
          content: line.content,
          cell_kind: line.type,
          comment_side: comment_side,
          comment_line_number: comment_line_number,
          comments: comments_by_key.fetch([file.path, comment_side, comment_line_number], []),
          hunk: nil
        )
      end
    end
  end

  def highlighted_diff_line(path, content)
    return "".html_safe if content.blank?

    marker = content[0]
    source = content[1..] || ""
    lexer = diff_lexer_for(path, source)
    tokens = diff_formatter.format(lexer.lex(source))
    marker_html = ERB::Util.html_escape(marker == " " ? "\u00A0" : marker)

    %(<span class="gh-code-marker">#{marker_html}</span><span class="gh-code">#{tokens}</span>).html_safe
  end

  def diff_layout_query(params_hash, **updates)
    current = params_hash.to_h.compact_blank
    merged = current.merge(updates.transform_keys(&:to_s))

    merged.reject { |_key, value| value.blank? }
  end

  def commit_group_title(date)
    "Commits on #{date.strftime('%b %-d, %Y')}"
  end

  def file_anchor_id(path)
    "file-#{path.parameterize(separator: '-')}"
  end

  def pull_request_author_name(comparison)
    comparison.commits.last&.author_name.presence || "You"
  end

  def author_initials(name)
    name.to_s.split(/\s+/).first(2).map { |part| part[0] }.join.upcase.presence || "Y"
  end

  def pull_request_timestamp(time)
    time.strftime("%b %-d, %Y")
  end

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

  def build_split_row(left:, right:, comment_side:, comment_line_number:, comments_by_key:, path:)
    comments = comments_by_key.fetch([path, comment_side, comment_line_number], [])

    SplitDiffRow.new(
      kind: :line,
      left:,
      right:,
      comment_side:,
      comment_line_number:,
      comments:,
      hunk: nil
    )
  end

  def diff_lexer_for(path, source)
    @diff_lexers ||= {}
    @diff_lexers[path] ||= Rouge::Lexer.guess(filename: path, source: source).new
  rescue Rouge::Guesser::Ambiguous, Rouge::Guesser::GuessError
    Rouge::Lexers::PlainText.new
  end

  def diff_formatter
    @diff_formatter ||= Rouge::Formatters::HTML.new
  end

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

    content_tag(:div, class: "gh-md-codeblock") do
      content_tag(:pre) do
        content_tag(:code, highlighted.html_safe)
      end
    end
  end

  def render_markdown_heading(line)
    match = line.match(/\A(#+)\s+(.+)\z/)
    level = match[1].length
    content_tag(:"h#{level}", render_markdown_inline(match[2]), class: "gh-md-heading")
  end

  def render_markdown_list(lines, start_index)
    items = []
    index = start_index

    while index < lines.length && list_item?(lines[index])
      items << lines[index]
      index += 1
    end

    @markdown_next_index = index

    content_tag(:ul, class: "gh-md-list") do
      safe_join(items.map { |item| render_markdown_list_item(item) })
    end
  end

  def render_markdown_list_item(line)
    match = line.match(/\A[*-]\s+\[(x| )\]\s+(.+)\z/i)

    if match
      checked = match[1].casecmp("x").zero?
      body = match[2]

      content_tag(:li, class: "gh-md-list-item gh-md-list-item--task") do
        check = tag.input(type: "checkbox", disabled: true, checked: checked, class: "gh-md-checkbox")
        safe_join([ check, content_tag(:span, render_markdown_inline(body)) ])
      end
    else
      body = line.sub(/\A[*-]\s+/, "")
      content_tag(:li, render_markdown_inline(body), class: "gh-md-list-item")
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
    content_tag(:p, render_markdown_inline(buffer.join(" ")), class: "gh-md-paragraph")
  end

  def render_markdown_inline(text)
    replacements = {}
    placeholder = 0

    processed = text.to_s.gsub(/\[([^\]]+)\]\(([^)]+)\)|`([^`]+)`|\*\*([^*]+)\*\*/) do
      key = "__MDTOKEN#{placeholder}__"
      placeholder += 1

      replacements[key] =
        if Regexp.last_match(1)
          link_to(CGI.escapeHTML(Regexp.last_match(1)), Regexp.last_match(2), target: "_blank", rel: "noreferrer")
        elsif Regexp.last_match(3)
          content_tag(:code, CGI.escapeHTML(Regexp.last_match(3)))
        else
          content_tag(:strong, CGI.escapeHTML(Regexp.last_match(4)))
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
