require "test_helper"

class GithubCliTest < ActiveSupport::TestCase
  test "available? delegates to which_gh presence" do
    # We can't easily stub in minitest 6, so test the underlying method.
    # which_gh returns a path or nil; available? wraps that in a boolean.
    result = GithubCli.available?
    if GithubCli.which_gh.present?
      assert result
    else
      assert_not result
    end
  end

  test "has_remote? returns false for a repo with no remote" do
    with_sample_repository do |fixture|
      cli = GithubCli.new(repo_path: fixture.path)
      assert_not cli.has_remote?
    end
  end

  test "remote_branch_exists? returns false for a repo with no remote" do
    with_sample_repository do |fixture|
      cli = GithubCli.new(repo_path: fixture.path)
      assert_not cli.remote_branch_exists?("main")
    end
  end
end
