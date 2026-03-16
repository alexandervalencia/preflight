require "test_helper"

class PullRequestReviewTest < ActionDispatch::IntegrationTest
  test "shows a commits index page and steps through individual commits" do
    with_sample_repository do |fixture|
      repository = create_local_repository!(fixture)
      pull_request = PullRequest.create!(local_repository: repository, source_branch: "feature", base_branch: "main")

      get repository_pull_path(repository, pull_request)
      assert_select "a[href='#{repository_pull_commits_path(repository, pull_request)}']", text: /Commits/

      get repository_pull_commits_path(repository, pull_request)

      assert_response :success
      assert_select "h3", text: /Commits on/
      assert_select "[data-role='commit-list-item']", text: /Add widget/
      assert_select "[data-role='commit-list-item']", text: /Refine widget/

      get repository_pull_commit_path(repository, pull_request, fixture.feature_commits[:refine_widget])

      assert_response :success
      assert_select ".pf-page--wide"
      assert_select "h1", text: "feature"
      assert_select "[data-role='commit-summary']", text: /Refine widget/
      assert_select "[data-role='file-tree']", text: /app/
      assert_select "[data-role='file-tree']", text: /models/
      assert_select "[data-role='file-tree']", text: /widget\.rb/
    end
  end
end
