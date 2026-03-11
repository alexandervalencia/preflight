require "open3"

class GitRepository
  Branch = Data.define(:name, :current)
  CommitSummary = Data.define(:sha, :short_sha, :message, :body, :author_name, :authored_at)
  DiffLine = Data.define(:type, :content, :old_number, :new_number)
  DiffFile = Data.define(:path, :status, :old_path, :lines)
  Comparison = Data.define(:base, :head, :commits, :files)
  CommitDetails = Data.define(:sha, :short_sha, :message, :body, :author_name, :authored_at, :files)

  def self.valid_repository?(path)
    return false unless path.present? && Dir.exist?(path)

    _stdout, _stderr, status = Open3.capture3("git", "rev-parse", "--is-inside-work-tree", chdir: path)
    status.success?
  rescue Errno::ENOENT
    false
  end

  def initialize(path:)
    @path = path
  end

  def branches
    git("for-each-ref", "--format=%(refname:short)\t%(HEAD)", "refs/heads").each_line.map do |line|
      name, current = line.strip.split("\t", 2)
      Branch.new(name:, current: current == "*")
    end.sort_by(&:name)
  end

  def current_branch
    git("branch", "--show-current")
  end

  def default_branch
    remote_head = git("symbolic-ref", "--quiet", "--short", "refs/remotes/origin/HEAD", allow_failure: true)
    return remote_head.split("/").last if remote_head.present?
    return "main" if branch_exists?("main")
    return "master" if branch_exists?("master")

    current_branch
  end

  def branch_head(branch_name)
    git("rev-parse", branch_name)
  end

  def compare(base:, head:)
    Comparison.new(
      base: base,
      head: head,
      commits: commits_between(base:, head:),
      files: compare_files(revision: "#{base}...#{head}")
    )
  end

  def commit(sha)
    metadata = parse_commit_metadata(git("show", "--quiet", "--format=%H%x1f%h%x1f%s%x1f%b%x1f%an%x1f%aI", sha))

    CommitDetails.new(
      sha: metadata.sha,
      short_sha: metadata.short_sha,
      message: metadata.message,
      body: metadata.body,
      author_name: metadata.author_name,
      authored_at: metadata.authored_at,
      files: commit_files(sha:)
    )
  end

  def file_changed?(from:, to:, path:)
    return false if from == to

    _stdout, _stderr, status = Open3.capture3("git", "diff", "--quiet", "#{from}..#{to}", "--", path, chdir: @path)
    raise "git diff failed for #{path}" unless [0, 1].include?(status.exitstatus)

    status.exitstatus == 1
  end

  private

  CommitMetadata = Data.define(:sha, :short_sha, :message, :body, :author_name, :authored_at)

  def commits_between(base:, head:)
    output = git("log", "--reverse", "--format=%H%x1f%h%x1f%s%x1f%b%x1f%an%x1f%aI%x1e", "#{base}..#{head}")

    parse_records(output).map do |sha, short_sha, message, body, author_name, authored_at|
      CommitSummary.new(
        sha: sha,
        short_sha: short_sha,
        message: message,
        body: body.to_s.rstrip,
        author_name: author_name,
        authored_at: Time.iso8601(authored_at)
      )
    end
  end

  def compare_files(revision:)
    build_diff_files(
      patch_output: git("diff", "--find-renames", "--no-color", "--unified=3", revision),
      status_output: git("diff", "--find-renames", "--name-status", revision)
    )
  end

  def commit_files(sha:)
    build_diff_files(
      patch_output: git("show", "--find-renames", "--no-color", "--format=", "--unified=3", sha),
      status_output: git("show", "--find-renames", "--format=", "--name-status", sha)
    )
  end

  def build_diff_files(patch_output:, status_output:)
    patches = parse_patch_sections(patch_output)
    statuses = parse_name_status(status_output)

    statuses.map do |status|
      patch_lines = patches.fetch(status[:path], [])
      DiffFile.new(
        path: status[:path],
        status: status[:status],
        old_path: status[:old_path],
        lines: parse_diff_lines(patch_lines)
      )
    end
  end

  def parse_commit_metadata(output)
    sha, short_sha, message, body, author_name, authored_at = output.split("\u001f", 6)

    CommitMetadata.new(
      sha: sha,
      short_sha: short_sha,
      message: message,
      body: body.to_s.rstrip,
      author_name: author_name,
      authored_at: Time.iso8601(authored_at)
    )
  end

  def parse_records(output)
    output.split("\u001e").filter_map do |record|
      fields = record.strip.split("\u001f")
      next if fields.empty? || fields.first.blank?

      fields
    end
  end

  def parse_name_status(output)
    output.each_line.filter_map do |line|
      next if line.blank?

      fields = line.strip.split("\t")
      status_code = fields.first
      status = status_code[0]

      case status
      when "R"
        { status: "R", old_path: fields[1], path: fields[2] }
      else
        { status: status, old_path: nil, path: fields[1] }
      end
    end
  end

  def parse_patch_sections(patch)
    sections = {}
    current_path = nil
    current_lines = []

    patch.each_line do |line|
      if line.start_with?("diff --git ")
        sections[current_path] = current_lines if current_path
        current_path = line.split(" b/", 2).last.to_s.strip
        current_lines = []
      else
        current_lines << line
      end
    end

    sections[current_path] = current_lines if current_path
    sections
  end

  def parse_diff_lines(lines)
    parsed_lines = []
    old_number = nil
    new_number = nil

    lines.each do |line|
      if line.start_with?("@@")
        match = line.match(/-([0-9]+)(?:,\d+)? \+([0-9]+)(?:,\d+)?/)
        old_number = match[1].to_i
        new_number = match[2].to_i
        parsed_lines << DiffLine.new(type: :hunk, content: line.chomp, old_number: nil, new_number: nil)
        next
      end

      next if old_number.nil? && new_number.nil?

      case line
      when /\A /
        parsed_lines << DiffLine.new(type: :context, content: line.chomp, old_number: old_number, new_number: new_number)
        old_number += 1
        new_number += 1
      when /\A-/
        parsed_lines << DiffLine.new(type: :deletion, content: line.chomp, old_number: old_number, new_number: nil)
        old_number += 1
      when /\A\+/
        parsed_lines << DiffLine.new(type: :addition, content: line.chomp, old_number: nil, new_number: new_number)
        new_number += 1
      end
    end

    parsed_lines
  end

  def git(*args, allow_failure: false)
    stdout, stderr, status = Open3.capture3("git", *args, chdir: @path)
    return stdout.strip if status.success?
    return "" if allow_failure

    raise "git #{args.join(' ')} failed: #{stderr}"
  end

  def branch_exists?(branch_name)
    _stdout, _stderr, status = Open3.capture3("git", "rev-parse", "--verify", "--quiet", "refs/heads/#{branch_name}", chdir: @path)
    status.success?
  end
end
