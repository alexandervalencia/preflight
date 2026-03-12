require "rouge"
require "cgi"

module PullRequestsHelper
  FileViewState = Data.define(:label, :css_class, :mark_viewed)
  SplitDiffCell = Data.define(:number, :content, :kind)
  SplitDiffRow = Data.define(:kind, :left, :right, :comment_side, :comment_line_number, :comments, :hunk)
  UnifiedDiffRow = Data.define(:kind, :left_number, :right_number, :content, :cell_kind, :comment_side, :comment_line_number, :comments, :hunk)
  FileTreeNode = Data.define(:name, :path, :children, :file, :level, :directory)

  def comment_target_for(line)
    return ["left", line.old_number] if line.type == :deletion
    return ["right", line.new_number] if line.new_number.present?

    [nil, nil]
  end

  def diff_line_class(line)
    "diff-line diff-line--#{line.type}"
  end

  def file_view_state(pull_request, viewed_file)
    return FileViewState.new(label: "Viewed", css_class: "view-state--unviewed", mark_viewed: true) unless viewed_file
    return FileViewState.new(label: "Viewed", css_class: "view-state--viewed", mark_viewed: false) if viewed_file.current?(repository: pull_request.git_repository)

    FileViewState.new(label: "Viewed", css_class: "view-state--new", mark_viewed: true)
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

  def file_tree_nodes(files)
    root = {}

    files.each do |file|
      parts = file.path.split("/")
      cursor = root

      parts.each_with_index do |part, index|
        cursor[part] ||= { children: {}, file: nil, path: parts.first(index + 1).join("/") }
        node = cursor[part]

        if index == parts.length - 1
          node[:file] = file
        end

        cursor = node[:children]
      end
    end

    flatten_file_tree(root)
  end

  def ordered_diff_files(files)
    file_tree_nodes(files).filter_map(&:file)
  end

  def octicon(name, size: 16, class_name: nil)
    path = case name
    when :chevron_down
      '<path d="M12.78 5.22a.75.75 0 0 1 0 1.06L8.53 10.53a.75.75 0 0 1-1.06 0L3.22 6.28a.75.75 0 1 1 1.06-1.06L8 8.94l3.72-3.72a.75.75 0 0 1 1.06 0Z"/>'
    when :sidebar_collapse
      '<path d="M2.75 2h10.5c.966 0 1.75.784 1.75 1.75v8.5A1.75 1.75 0 0 1 13.25 14H2.75A1.75 1.75 0 0 1 1 12.25v-8.5C1 2.784 1.784 2 2.75 2Zm0 1.5a.25.25 0 0 0-.25.25v8.5c0 .138.112.25.25.25h2.5v-9Zm4 9h6.5a.25.25 0 0 0 .25-.25v-8.5a.25.25 0 0 0-.25-.25h-6.5Zm-2.28-5.03 1.47-1.47a.75.75 0 1 1 1.06 1.06L6.06 8l.94.94a.75.75 0 1 1-1.06 1.06L4.47 8.53a.75.75 0 0 1 0-1.06Z"/>'
    when :search
      '<path d="M10.28 10.28a.75.75 0 0 1 1.06 0l3.44 3.44a.75.75 0 1 1-1.06 1.06l-3.44-3.44a6 6 0 1 1 1.06-1.06ZM6.5 11a4.5 4.5 0 1 0 0-9 4.5 4.5 0 0 0 0 9Z"/>'
    when :git_commit
      '<path d="M10.5 8a2.5 2.5 0 1 1-4.95.5H2.75a.75.75 0 0 1 0-1.5h2.8a2.5 2.5 0 0 1 4.95.5h2.75a.75.75 0 0 1 0 1.5Zm-2.5 1a1 1 0 1 0 0-2 1 1 0 0 0 0 2Z"/>'
    when :filter
      '<path d="M1.75 3h12.5a.75.75 0 0 1 .53 1.28L10 9.06v3.69a.75.75 0 0 1-1.2.6l-2-1.5a.75.75 0 0 1-.3-.6V9.06L1.22 4.28A.75.75 0 0 1 1.75 3Z"/>'
    when :gear
      '<path d="M8 1.75a.75.75 0 0 1 .75.75v.58a4.73 4.73 0 0 1 1.3.54l.4-.4a.75.75 0 0 1 1.06 0l1.27 1.27a.75.75 0 0 1 0 1.06l-.4.4c.24.41.42.85.54 1.3h.58a.75.75 0 0 1 .75.75v1.8a.75.75 0 0 1-.75.75h-.58a4.73 4.73 0 0 1-.54 1.3l.4.4a.75.75 0 0 1 0 1.06l-1.27 1.27a.75.75 0 0 1-1.06 0l-.4-.4a4.73 4.73 0 0 1-1.3.54v.58a.75.75 0 0 1-.75.75h-1.8a.75.75 0 0 1-.75-.75v-.58a4.73 4.73 0 0 1-1.3-.54l-.4.4a.75.75 0 0 1-1.06 0L2.22 12.8a.75.75 0 0 1 0-1.06l.4-.4a4.73 4.73 0 0 1-.54-1.3H1.5a.75.75 0 0 1-.75-.75v-1.8A.75.75 0 0 1 1.5 6.75h.58c.12-.45.3-.89.54-1.3l-.4-.4a.75.75 0 0 1 0-1.06L3.49 2.72a.75.75 0 0 1 1.06 0l.4.4c.41-.24.85-.42 1.3-.54V2.5A.75.75 0 0 1 7 1.75Zm0 4a2.15 2.15 0 1 0 0 4.3 2.15 2.15 0 0 0 0-4.3Z"/>'
    when :info
      '<path d="M8 1.5a6.5 6.5 0 1 1 0 13 6.5 6.5 0 0 1 0-13Zm0 1.5a5 5 0 1 0 0 10A5 5 0 0 0 8 3Zm0 2.25a.9.9 0 1 1 0 1.8.9.9 0 0 1 0-1.8Zm1 6.25a.75.75 0 0 1 0 1.5H7a.75.75 0 0 1 0-1.5h.25V8.25H7a.75.75 0 0 1 0-1.5h1A.75.75 0 0 1 8.75 7.5v4H9Z"/>'
    when :comment
      '<path d="M1.75 2.5h12.5c.414 0 .75.336.75.75v7.5a.75.75 0 0 1-.75.75H9.31l-2.78 2.34a.75.75 0 0 1-1.23-.57V11.5H1.75a.75.75 0 0 1-.75-.75v-7.5c0-.414.336-.75.75-.75Zm.75 1.5V10h3.55a.75.75 0 0 1 .75.75v.92l1.72-1.44a.75.75 0 0 1 .48-.18h4.5V4Z"/>'
    when :kebab
      '<path d="M8 4.75a1.25 1.25 0 1 1 0-2.5 1.25 1.25 0 0 1 0 2.5Zm0 5.5a1.25 1.25 0 1 1 0-2.5 1.25 1.25 0 0 1 0 2.5Zm0 5.5a1.25 1.25 0 1 1 0-2.5 1.25 1.25 0 0 1 0 2.5Z"/>'
    when :file
      '<path d="M3.75 1h5.19c.2 0 .39.08.53.22l3.31 3.31c.14.14.22.33.22.53v8.19A1.75 1.75 0 0 1 11.25 15h-7.5A1.75 1.75 0 0 1 2 13.25v-10.5C2 1.78 2.78 1 3.75 1Zm0 1.5a.25.25 0 0 0-.25.25v10.5c0 .14.11.25.25.25h7.5a.25.25 0 0 0 .25-.25V5.81L8.19 2.5Zm4.5.06V5h2.44Z"/>'
    when :file_directory
      '<path d="M1.75 2h3.1c.27 0 .53.11.72.3l1 1h6.68c.97 0 1.75.78 1.75 1.75v6.2c0 .97-.78 1.75-1.75 1.75H2.75A1.75 1.75 0 0 1 1 11.25V3.75C1 2.78 1.78 2 2.75 2Zm0 1.5a.25.25 0 0 0-.25.25v7.5c0 .14.11.25.25.25h10.5a.25.25 0 0 0 .25-.25v-6.2A.25.25 0 0 0 12.25 4.8H6.26a.75.75 0 0 1-.53-.22l-1-1A.25.25 0 0 0 4.56 3.5Z"/>'
    when :copy
      '<path d="M0 6.75C0 5.78.78 5 1.75 5h6.5C9.22 5 10 5.78 10 6.75v6.5C10 14.22 9.22 15 8.25 15h-6.5A1.75 1.75 0 0 1 0 13.25Zm1.75-.25a.25.25 0 0 0-.25.25v6.5c0 .14.11.25.25.25h6.5a.25.25 0 0 0 .25-.25v-6.5a.25.25 0 0 0-.25-.25Zm10.5-5A1.75 1.75 0 0 1 14 3.25v6.5a.75.75 0 0 1-1.5 0v-6.5a.25.25 0 0 0-.25-.25h-6.5a.75.75 0 0 1 0-1.5Z"/>'
    when :expand
      '<path d="M3.75 2h2.5a.75.75 0 0 1 0 1.5H5.56L7.28 5.22a.75.75 0 1 1-1.06 1.06L4.5 4.56v.69a.75.75 0 0 1-1.5 0v-2.5C3 2.34 3.34 2 3.75 2Zm5 0h2.5c.41 0 .75.34.75.75v2.5a.75.75 0 0 1-1.5 0v-.69L8.78 6.28a.75.75 0 1 1-1.06-1.06L9.44 3.5h-.69a.75.75 0 0 1 0-1.5ZM4.5 10.44l1.72-1.72a.75.75 0 1 1 1.06 1.06L5.56 11.5h.69a.75.75 0 0 1 0 1.5h-2.5A.75.75 0 0 1 3 12.25v-2.5a.75.75 0 0 1 1.5 0Zm7 0v2.5a.75.75 0 0 1-.75.75h-2.5a.75.75 0 0 1 0-1.5h.69L7.72 9.78a.75.75 0 1 1 1.06-1.06l1.72 1.72v-.69a.75.75 0 0 1 1.5 0Z"/>'
    else
      '<circle cx="8" cy="8" r="6"/>'
    end

    classes = ["octicon", class_name].compact.join(" ")
    %(<svg aria-hidden="true" class="#{classes}" width="#{size}" height="#{size}" viewBox="0 0 16 16" fill="currentColor">#{path}</svg>).html_safe
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

  def flatten_file_tree(tree, level: 0)
    tree
      .sort_by { |name, node| [node[:file] ? 1 : 0, name] }
      .flat_map do |name, node|
        collapsed_name, collapsed_node = collapse_tree_node(name, node)

        if collapsed_node[:file]
          [
            FileTreeNode.new(
              name: collapsed_node[:file].path.split("/").last,
              path: collapsed_node[:file].path,
              children: [],
              file: collapsed_node[:file],
              level:,
              directory: false
            )
          ]
        else
          [
            FileTreeNode.new(
              name: collapsed_name,
              path: collapsed_node[:path],
              children: [],
              file: nil,
              level:,
              directory: true
            ),
            *flatten_file_tree(collapsed_node[:children], level: level + 1)
          ]
        end
      end
  end

  def collapse_tree_node(name, node)
    collapsed_name = name
    current_node = node

    while current_node[:file].nil? &&
      current_node[:children].size == 1 &&
      current_node[:children].values.first[:file].nil?
      child_name, child_node = current_node[:children].first
      collapsed_name = "#{collapsed_name}/#{child_name}"
      current_node = child_node
    end

    [collapsed_name, current_node]
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
