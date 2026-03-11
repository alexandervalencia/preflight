require "rouge"

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
end
