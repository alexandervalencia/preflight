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

  def diffstat_blocks(additions, deletions)
    total = additions + deletions
    return "" if total == 0

    blocks = 5
    add_blocks = (additions.to_f / total * blocks).floor
    del_blocks = (deletions.to_f / total * blocks).floor

    # Ensure at least 1 block for non-zero counts
    add_blocks = 1 if additions > 0 && add_blocks == 0
    del_blocks = 1 if deletions > 0 && del_blocks == 0

    # Cap to exactly 5 blocks
    if add_blocks + del_blocks > blocks
      add_blocks = blocks - del_blocks if del_blocks <= blocks
      del_blocks = blocks - add_blocks if add_blocks + del_blocks > blocks
    end

    neutral = blocks - add_blocks - del_blocks

    parts = []
    add_blocks.times { parts << content_tag(:span, "", class: "gh-diffstat-block gh-diffstat-block--added") }
    del_blocks.times { parts << content_tag(:span, "", class: "gh-diffstat-block gh-diffstat-block--deleted") }
    neutral.times { parts << content_tag(:span, "", class: "gh-diffstat-block gh-diffstat-block--neutral") }
    safe_join(parts)
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
      '<path d="m4.427 7.427 3.396 3.396a.25.25 0 0 0 .354 0l3.396-3.396A.25.25 0 0 0 11.396 7H4.604a.25.25 0 0 0-.177.427Z"></path>'
    when :sidebar_collapse
      '<path d="M6.823 7.823a.25.25 0 0 1 0 .354l-2.396 2.396A.25.25 0 0 1 4 10.396V5.604a.25.25 0 0 1 .427-.177Z"></path><path d="M1.75 0h12.5C15.216 0 16 .784 16 1.75v12.5A1.75 1.75 0 0 1 14.25 16H1.75A1.75 1.75 0 0 1 0 14.25V1.75C0 .784.784 0 1.75 0ZM1.5 1.75v12.5c0 .138.112.25.25.25H9.5v-13H1.75a.25.25 0 0 0-.25.25ZM11 14.5h3.25a.25.25 0 0 0 .25-.25V1.75a.25.25 0 0 0-.25-.25H11Z"></path>'
    when :sidebar_expand
      '<path d="m4.177 7.823 2.396-2.396A.25.25 0 0 1 7 5.604v4.792a.25.25 0 0 1-.427.177L4.177 8.177a.25.25 0 0 1 0-.354Z"></path><path d="M0 1.75C0 .784.784 0 1.75 0h12.5C15.216 0 16 .784 16 1.75v12.5A1.75 1.75 0 0 1 14.25 16H1.75A1.75 1.75 0 0 1 0 14.25Zm1.75-.25a.25.25 0 0 0-.25.25v12.5c0 .138.112.25.25.25H9.5v-13Zm12.5 13a.25.25 0 0 0 .25-.25V1.75a.25.25 0 0 0-.25-.25H11v13Z"></path>'
    when :git_commit
      '<path d="M11.93 8.5a4.002 4.002 0 0 1-7.86 0H.75a.75.75 0 0 1 0-1.5h3.32a4.002 4.002 0 0 1 7.86 0h3.32a.75.75 0 0 1 0 1.5Zm-1.43-.75a2.5 2.5 0 1 0-5 0 2.5 2.5 0 0 0 5 0Z"></path>'
    when :gear
      '<path d="M8 0a8.2 8.2 0 0 1 .701.031C9.444.095 9.99.645 10.16 1.29l.288 1.107c.018.066.079.158.212.224.231.114.454.243.668.386.123.082.233.09.299.071l1.103-.303c.644-.176 1.392.021 1.82.63.27.385.506.792.704 1.218.315.675.111 1.422-.364 1.891l-.814.806c-.049.048-.098.147-.088.294.016.257.016.515 0 .772-.01.147.038.246.088.294l.814.806c.475.469.679 1.216.364 1.891a7.977 7.977 0 0 1-.704 1.217c-.428.61-1.176.807-1.82.63l-1.102-.302c-.067-.019-.177-.011-.3.071a5.909 5.909 0 0 1-.668.386c-.133.066-.194.158-.211.224l-.29 1.106c-.168.646-.715 1.196-1.458 1.26a8.006 8.006 0 0 1-1.402 0c-.743-.064-1.289-.614-1.458-1.26l-.289-1.106c-.018-.066-.079-.158-.212-.224a5.738 5.738 0 0 1-.668-.386c-.123-.082-.233-.09-.299-.071l-1.103.303c-.644.176-1.392-.021-1.82-.63a8.12 8.12 0 0 1-.704-1.218c-.315-.675-.111-1.422.363-1.891l.815-.806c.05-.048.098-.147.088-.294a6.214 6.214 0 0 1 0-.772c.01-.147-.038-.246-.088-.294l-.815-.806C.635 6.045.431 5.298.746 4.623a7.92 7.92 0 0 1 .704-1.217c.428-.61 1.176-.807 1.82-.63l1.102.302c.067.019.177.011.3-.071.214-.143.437-.272.668-.386.133-.066.194-.158.211-.224l.29-1.106C6.009.645 6.556.095 7.299.03 7.53.01 7.764 0 8 0Zm-.571 1.525c-.036.003-.108.036-.137.146l-.289 1.105c-.147.561-.549.967-.998 1.189-.173.086-.34.183-.5.29-.417.278-.97.423-1.529.27l-1.103-.303c-.109-.03-.175.016-.195.045-.22.312-.412.644-.573.99-.014.031-.021.11.059.19l.815.806c.411.406.562.957.53 1.456a4.709 4.709 0 0 0 0 .582c.032.499-.119 1.05-.53 1.456l-.815.806c-.081.08-.073.159-.059.19.162.346.353.677.573.989.02.03.085.076.195.046l1.102-.303c.56-.153 1.113-.008 1.53.27.161.107.328.204.501.29.447.222.85.629.997 1.189l.289 1.105c.029.109.101.143.137.146a6.6 6.6 0 0 0 1.142 0c.036-.003.108-.036.137-.146l.289-1.105c.147-.561.549-.967.998-1.189.173-.086.34-.183.5-.29.417-.278.97-.423 1.529-.27l1.103.303c.109.029.175-.016.195-.045.22-.313.411-.644.573-.99.014-.031.021-.11-.059-.19l-.815-.806c-.411-.406-.562-.957-.53-1.456a4.709 4.709 0 0 0 0-.582c-.032-.499.119-1.05.53-1.456l.815-.806c.081-.08.073-.159.059-.19a6.464 6.464 0 0 0-.573-.989c-.02-.03-.085-.076-.195-.046l-1.102.303c-.56.153-1.113.008-1.53-.27a4.44 4.44 0 0 0-.501-.29c-.447-.222-.85-.629-.997-1.189l-.289-1.105c-.029-.11-.101-.143-.137-.146a6.6 6.6 0 0 0-1.142 0ZM11 8a3 3 0 1 1-6 0 3 3 0 0 1 6 0ZM9.5 8a1.5 1.5 0 1 0-3.001.001A1.5 1.5 0 0 0 9.5 8Z"></path>'
    when :comment
      '<path d="M1.75 1h8.5c.966 0 1.75.784 1.75 1.75v5.5A1.75 1.75 0 0 1 10.25 10H7.061l-2.574 2.573A1.458 1.458 0 0 1 2 11.543V10h-.25A1.75 1.75 0 0 1 0 8.25v-5.5C0 1.784.784 1 1.75 1ZM1.5 2.75v5.5c0 .138.112.25.25.25h1a.75.75 0 0 1 .75.75v2.19l2.72-2.72a.749.749 0 0 1 .53-.22h3.5a.25.25 0 0 0 .25-.25v-5.5a.25.25 0 0 0-.25-.25h-8.5a.25.25 0 0 0-.25.25Zm13 2a.25.25 0 0 0-.25-.25h-.5a.75.75 0 0 1 0-1.5h.5c.966 0 1.75.784 1.75 1.75v5.5A1.75 1.75 0 0 1 14.25 12H14v1.543a1.458 1.458 0 0 1-2.487 1.03L9.22 12.28a.749.749 0 0 1 .326-1.275.749.749 0 0 1 .734.215l2.22 2.22v-2.19a.75.75 0 0 1 .75-.75h1a.25.25 0 0 0 .25-.25Z"></path>'
    when :kebab
      '<path d="M8 4.75a1.25 1.25 0 1 1 0-2.5 1.25 1.25 0 0 1 0 2.5Zm0 5.5a1.25 1.25 0 1 1 0-2.5 1.25 1.25 0 0 1 0 2.5Zm0 5.5a1.25 1.25 0 1 1 0-2.5 1.25 1.25 0 0 1 0 2.5Z"/>'
    when :file
      '<path d="M1 1.75C1 .784 1.784 0 2.75 0h7.586c.464 0 .909.184 1.237.513l2.914 2.914c.329.328.513.773.513 1.237v9.586A1.75 1.75 0 0 1 13.25 16H2.75A1.75 1.75 0 0 1 1 14.25Zm1.75-.25a.25.25 0 0 0-.25.25v12.5c0 .138.112.25.25.25h10.5a.25.25 0 0 0 .25-.25V4.664a.25.25 0 0 0-.073-.177l-2.914-2.914a.25.25 0 0 0-.177-.073ZM8 3.25a.75.75 0 0 1 .75.75v1.5h1.5a.75.75 0 0 1 0 1.5h-1.5v1.5a.75.75 0 0 1-1.5 0V7h-1.5a.75.75 0 0 1 0-1.5h1.5V4A.75.75 0 0 1 8 3.25Zm-3 8a.75.75 0 0 1 .75-.75h4.5a.75.75 0 0 1 0 1.5h-4.5a.75.75 0 0 1-.75-.75Z"></path>'
    when :file_directory
      '<path d="M0 2.75C0 1.784.784 1 1.75 1H5c.55 0 1.07.26 1.4.7l.9 1.2a.25.25 0 0 0 .2.1h6.75c.966 0 1.75.784 1.75 1.75v8.5A1.75 1.75 0 0 1 14.25 15H1.75A1.75 1.75 0 0 1 0 13.25Zm1.75-.25a.25.25 0 0 0-.25.25v10.5c0 .138.112.25.25.25h12.5a.25.25 0 0 0 .25-.25v-8.5a.25.25 0 0 0-.25-.25H7.5c-.55 0-1.07-.26-1.4-.7l-.9-1.2a.25.25 0 0 0-.2-.1Z"></path>'
    when :file_directory_open
      '<path d="M.513 1.513A1.75 1.75 0 0 1 1.75 1h3.5c.55 0 1.07.26 1.4.7l.9 1.2a.25.25 0 0 0 .2.1H13a1 1 0 0 1 1 1v.5H2.75a.75.75 0 0 0 0 1.5h11.978a1 1 0 0 1 .994 1.117L15 13.25A1.75 1.75 0 0 1 13.25 15H1.75A1.75 1.75 0 0 1 0 13.25V2.75c0-.464.184-.91.513-1.237Z"></path>'
    when :expand
      '<path d="m8.177.677 2.896 2.896a.25.25 0 0 1-.177.427H8.75v1.25a.75.75 0 0 1-1.5 0V4H5.104a.25.25 0 0 1-.177-.427L7.823.677a.25.25 0 0 1 .354 0ZM7.25 10.75a.75.75 0 0 1 1.5 0V12h2.146a.25.25 0 0 1 .177.427l-2.896 2.896a.25.25 0 0 1-.354 0l-2.896-2.896A.25.25 0 0 1 5.104 12H7.25v-1.25Zm-5-2a.75.75 0 0 0 0-1.5h-.5a.75.75 0 0 0 0 1.5h.5ZM6 8a.75.75 0 0 1-.75.75h-.5a.75.75 0 0 1 0-1.5h.5A.75.75 0 0 1 6 8Zm2.25.75a.75.75 0 0 0 0-1.5h-.5a.75.75 0 0 0 0 1.5h.5ZM12 8a.75.75 0 0 1-.75.75h-.5a.75.75 0 0 1 0-1.5h.5A.75.75 0 0 1 12 8Zm2.25.75a.75.75 0 0 0 0-1.5h-.5a.75.75 0 0 0 0 1.5h.5Z"></path>'
    when :versions
      '<path d="M7.75 14A1.75 1.75 0 0 1 6 12.25v-8.5C6 2.784 6.784 2 7.75 2h6.5c.966 0 1.75.784 1.75 1.75v8.5A1.75 1.75 0 0 1 14.25 14Zm-.25-1.75c0 .138.112.25.25.25h6.5a.25.25 0 0 0 .25-.25v-8.5a.25.25 0 0 0-.25-.25h-6.5a.25.25 0 0 0-.25.25ZM4.9 3.508a.75.75 0 0 1-.274 1.025.249.249 0 0 0-.126.217v6.5c0 .09.048.173.126.217a.75.75 0 0 1-.752 1.298A1.75 1.75 0 0 1 3 11.25v-6.5c0-.649.353-1.214.874-1.516a.75.75 0 0 1 1.025.274ZM1.625 5.533h.001a.249.249 0 0 0-.126.217v4.5c0 .09.048.173.126.217a.75.75 0 0 1-.752 1.298A1.748 1.748 0 0 1 0 10.25v-4.5a1.748 1.748 0 0 1 .873-1.516.75.75 0 1 1 .752 1.299Z"></path>'
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
