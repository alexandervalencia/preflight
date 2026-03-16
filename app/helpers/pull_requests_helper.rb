module PullRequestsHelper
  SplitDiffCell = Data.define(:number, :content, :kind, :highlights) do
    def initialize(number:, content:, kind:, highlights: nil)
      super(number: number, content: content, kind: kind, highlights: highlights)
    end
  end
  SplitDiffRow = Data.define(:kind, :left, :right, :hunk)
  UnifiedDiffRow = Data.define(:kind, :left_number, :right_number, :content, :cell_kind, :hunk)
  FileTreeNode = Data.define(:name, :path, :children, :file, :level, :directory)

  def format_commit_message(text)
    h(text).gsub(/`([^`]+)`/) { content_tag(:code, $1) }.html_safe
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

  def pull_request_author_name(comparison)
    comparison.commits.last&.author_name.presence || "You"
  end

  def author_initials(name)
    name.to_s.split(/\s+/).first(2).map { |part| part[0] }.join.upcase.presence || "Y"
  end

  def pull_request_timestamp(time)
    time.strftime("%b %-d, %Y")
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

  private

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
end
