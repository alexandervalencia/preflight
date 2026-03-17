require "test_helper"

class GithubExportsControllerTest < ActionDispatch::IntegrationTest
  test "POST github_export redirects with alert when gh is not available" do
    with_sample_repository do |fixture|
      local_repository = create_local_repository!(fixture)
      pull_request = PullRequest.create!(
        local_repository:, source_branch: "feature", base_branch: "main"
      )

      # Override available? to return false for this test
      original_method = GithubCli.method(:available?)
      GithubCli.define_singleton_method(:available?) { false }

      post repository_pull_github_export_path(local_repository, pull_request)

      GithubCli.define_singleton_method(:available?, original_method)

      assert_redirected_to repository_pull_path(local_repository, pull_request)
      assert_match "not installed", flash[:alert]
    end
  end

  test "POST github_export redirects with alert when repo has no remote" do
    with_sample_repository do |fixture|
      local_repository = create_local_repository!(fixture)
      pull_request = PullRequest.create!(
        local_repository:, source_branch: "feature", base_branch: "main"
      )

      # gh is available but the test repo has no remote
      original_method = GithubCli.method(:available?)
      GithubCli.define_singleton_method(:available?) { true }

      post repository_pull_github_export_path(local_repository, pull_request)

      GithubCli.define_singleton_method(:available?, original_method)

      assert_redirected_to repository_pull_path(local_repository, pull_request)
      assert_match "no remote", flash[:alert]
    end
  end
end
