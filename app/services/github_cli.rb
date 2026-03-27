require "open3"

class GithubCli
  class Error < StandardError; end

  def self.available?
    which_gh.present?
  end

  def self.which_gh
    stdout, _, status = Open3.capture3("which", "gh")
    status.success? ? stdout.strip : nil
  rescue Errno::ENOENT
    nil
  end

  def initialize(repo_path:, remote: "origin")
    @repo_path = repo_path
    @remote = remote
  end

  def create_pull_request(title:, body:, base:, head:, draft: true)
    args = ["pr", "create", "--repo", remote_repo_name, "--title", title, "--body", body, "--base", base, "--head", head]
    args << "--draft" if draft

    stdout = gh(*args)
    stdout.strip
  end

  def pull_request_for_branch(branch)
    stdout = gh("pr", "list", "--repo", remote_repo_name, "--head", branch, "--json", "url", "--limit", "1", allow_failure: true)
    return nil if stdout.blank?

    prs = JSON.parse(stdout)
    prs.first&.dig("url")
  rescue JSON::ParserError
    nil
  end

  def push_branch(branch)
    stdout, stderr, status = Open3.capture3("git", "push", "-u", @remote, branch, chdir: @repo_path)
    raise Error, "git push failed: #{stderr}" unless status.success?

    stdout.strip
  end

  def remote_branch_exists?(branch)
    stdout, _, status = Open3.capture3("git", "ls-remote", "--heads", @remote, branch, chdir: @repo_path)
    status.success? && stdout.strip.present?
  rescue Errno::ENOENT
    false
  end

  def has_remote?
    stdout, _, status = Open3.capture3("git", "remote", "get-url", @remote, chdir: @repo_path)
    status.success? && stdout.strip.present?
  rescue Errno::ENOENT
    false
  end

  def remote_repo_name
    url = Open3.capture3("git", "remote", "get-url", @remote, chdir: @repo_path).first.strip
    # Extract owner/repo from git@github.com:owner/repo.git or https://github.com/owner/repo.git
    match = url.match(%r{[/:]([^/]+/[^/]+?)(?:\.git)?$})
    match ? match[1] : url
  end

  private

  def gh(*args, allow_failure: false)
    stdout, stderr, status = Open3.capture3("gh", *args, chdir: @repo_path)
    return stdout.strip if status.success?
    return "" if allow_failure

    raise Error, "gh #{args.join(' ')} failed: #{stderr}"
  end
end
