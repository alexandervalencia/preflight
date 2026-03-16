require "rouge"

module DiffHelper
  def split_diff_rows(file)
    rows = []
    lines = file.lines
    index = 0

    while index < lines.length
      line = lines[index]

      if line.type == :hunk
        rows << PullRequestsHelper::SplitDiffRow.new(
          kind: :hunk,
          left: nil,
          right: nil,
          hunk: line.content
        )
        index += 1
        next
      end

      if line.type == :deletion
        deletions = []
        while index < lines.length && lines[index].type == :deletion
          deletions << lines[index]
          index += 1
        end
        additions = []
        while index < lines.length && lines[index].type == :addition
          additions << lines[index]
          index += 1
        end

        max = [deletions.length, additions.length].max
        max.times do |i|
          del = deletions[i]
          add = additions[i]
          old_hl, new_hl = if del && add
            compute_word_highlights(del.content, add.content)
          else
            [nil, nil]
          end
          left = del ? PullRequestsHelper::SplitDiffCell.new(number: del.old_number, content: del.content, kind: :deletion, highlights: old_hl) : PullRequestsHelper::SplitDiffCell.new(number: nil, content: "", kind: :empty)
          right = add ? PullRequestsHelper::SplitDiffCell.new(number: add.new_number, content: add.content, kind: :addition, highlights: new_hl) : PullRequestsHelper::SplitDiffCell.new(number: nil, content: "", kind: :empty)
          rows << build_split_row(left: left, right: right)
        end
        next
      end

      if line.type == :addition
        rows << build_split_row(
          left: PullRequestsHelper::SplitDiffCell.new(number: nil, content: "", kind: :empty),
          right: PullRequestsHelper::SplitDiffCell.new(number: line.new_number, content: line.content, kind: :addition)
        )
        index += 1
        next
      end

      rows << build_split_row(
        left: PullRequestsHelper::SplitDiffCell.new(number: line.old_number, content: line.content, kind: :context),
        right: PullRequestsHelper::SplitDiffCell.new(number: line.new_number, content: line.content, kind: :context)
      )

      index += 1
    end

    rows
  end

  def unified_diff_rows(file)
    file.lines.map do |line|
      if line.type == :hunk
        PullRequestsHelper::UnifiedDiffRow.new(
          kind: :hunk,
          left_number: nil,
          right_number: nil,
          content: nil,
          cell_kind: :hunk,
          hunk: line.content
        )
      else
        PullRequestsHelper::UnifiedDiffRow.new(
          kind: :line,
          left_number: line.old_number,
          right_number: line.new_number,
          content: line.content,
          cell_kind: line.type,
          hunk: nil
        )
      end
    end
  end

  def highlighted_diff_line(path, content, highlights: nil)
    return "".html_safe if content.blank?

    marker = content[0]
    source = content[1..] || ""
    lexer = diff_lexer_for(path, source)
    tokens = diff_formatter.format(lexer.lex(source))
    marker_html = ERB::Util.html_escape(marker == " " ? "\u00A0" : marker)

    if highlights.present?
      tokens = apply_word_highlights(tokens, highlights)
    end

    %(<span class="pf-code-marker">#{marker_html}</span><span class="pf-code">#{tokens}</span>).html_safe
  end

  def compute_word_highlights(old_content, new_content)
    old_src = (old_content || "")[1..] || ""
    new_src = (new_content || "")[1..] || ""

    old_tokens = old_src.scan(/\w+|\S|\s+/)
    new_tokens = new_src.scan(/\w+|\S|\s+/)

    lcs = lcs_table(old_tokens, new_tokens)
    old_ranges = diff_ranges(old_tokens, new_tokens, lcs, :old)
    new_ranges = diff_ranges(old_tokens, new_tokens, lcs, :new)

    [old_ranges, new_ranges]
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
    neutral = blocks - add_blocks - del_blocks

    parts = []
    add_blocks.times { parts << content_tag(:span, "", class: "pf-diffstat-block pf-diffstat-block--added") }
    del_blocks.times { parts << content_tag(:span, "", class: "pf-diffstat-block pf-diffstat-block--deleted") }
    neutral.times { parts << content_tag(:span, "", class: "pf-diffstat-block pf-diffstat-block--neutral") }
    content_tag(:span, safe_join(parts), class: "pf-diffstat-blocks")
  end

  def diff_line_class(line)
    "diff-line diff-line--#{line.type}"
  end

  def diff_layout_query(params_hash, **updates)
    current = params_hash.to_h.compact_blank
    merged = current.merge(updates.transform_keys(&:to_s))

    merged.reject { |_key, value| value.blank? }
  end

  private

  def build_split_row(left:, right:)
    PullRequestsHelper::SplitDiffRow.new(
      kind: :line,
      left:,
      right:,
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

  def lcs_table(a, b)
    m = a.length
    n = b.length
    table = Array.new(m + 1) { Array.new(n + 1, 0) }
    (1..m).each do |i|
      (1..n).each do |j|
        table[i][j] = if a[i - 1] == b[j - 1]
          table[i - 1][j - 1] + 1
        else
          [table[i - 1][j], table[i][j - 1]].max
        end
      end
    end
    table
  end

  def diff_ranges(old_tokens, new_tokens, lcs, side)
    ranges = []
    i = old_tokens.length
    j = new_tokens.length
    changed_indices = []

    while i > 0 && j > 0
      if old_tokens[i - 1] == new_tokens[j - 1]
        i -= 1
        j -= 1
      elsif lcs[i - 1][j] >= lcs[i][j - 1]
        i -= 1
        changed_indices.unshift(i) if side == :old
      else
        j -= 1
        changed_indices.unshift(j) if side == :new
      end
    end

    while i > 0
      i -= 1
      changed_indices.unshift(i) if side == :old
    end
    while j > 0
      j -= 1
      changed_indices.unshift(j) if side == :new
    end

    tokens = side == :old ? old_tokens : new_tokens
    pos = 0
    changed_indices.each do |idx|
      offset = tokens[0...idx].sum(&:length)
      len = tokens[idx].length
      ranges << (offset...(offset + len))
    end

    merge_adjacent_ranges(ranges)
  end

  def merge_adjacent_ranges(ranges)
    return [] if ranges.empty?
    merged = [ranges.first]
    ranges[1..].each do |r|
      if r.begin <= merged.last.end
        merged[-1] = (merged.last.begin...[merged.last.end, r.end].max)
      else
        merged << r
      end
    end
    merged
  end

  def apply_word_highlights(html, ranges)
    return html if ranges.empty?

    # Map source-text character positions to positions in the HTML string,
    # skipping over HTML tags and counting HTML entities as single chars
    text_pos = 0
    source_to_html = {}
    i = 0

    while i < html.length
      if html[i] == "<"
        # Skip entire tag
        close = html.index(">", i)
        i = close ? close + 1 : i + 1
      elsif html[i] == "&"
        # HTML entity — maps to one source character
        source_to_html[text_pos] = i
        text_pos += 1
        semi = html.index(";", i)
        i = semi ? semi + 1 : i + 1
      else
        source_to_html[text_pos] = i
        text_pos += 1
        i += 1
      end
    end
    source_to_html[text_pos] = html.length

    result = +""
    last_html_pos = 0
    css_class = "pf-word-highlight"

    ranges.each do |range|
      start_html = source_to_html[range.begin]
      end_html = source_to_html[range.end]
      next unless start_html && end_html

      result << html[last_html_pos...start_html]
      result << %(<mark class="#{css_class}">)
      result << html[start_html...end_html]
      result << %(</mark>)
      last_html_pos = end_html
    end

    result << html[last_html_pos..]
    result
  end
end
