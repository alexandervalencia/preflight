require "test_helper"

class PullRequestReviewTest < ActionDispatch::IntegrationTest
  test "adds an inline comment on the overall pull request diff" do
    with_sample_repository do |fixture|
      repository = create_local_repository!(fixture)
      pull_request = PullRequest.create!(local_repository: repository, source_branch: "feature", base_branch: "main")

      post pull_request_inline_comments_path(pull_request), params: {
        inline_comment: {
          path: "app/models/widget.rb",
          side: "right",
          line_number: 3,
          body: "Ship this from the PR view."
        },
        redirect_to: repository_pull_request_files_path(repository, pull_request)
      }

      assert_redirected_to repository_pull_request_files_path(repository, pull_request)
      follow_redirect!
      assert_select "[data-role='inline-comment']", text: /Ship this from the PR view\./
      assert_select "[data-role='file-tree-count']", text: "1"
    end
  end

  test "shows a commits index page and steps through individual commits" do
    with_sample_repository do |fixture|
      repository = create_local_repository!(fixture)
      pull_request = PullRequest.create!(local_repository: repository, source_branch: "feature", base_branch: "main")

      get repository_pull_request_path(repository, pull_request)
      assert_select "a[href='#{pull_request_commits_path(pull_request)}']", text: /Commits/

      get pull_request_commits_path(pull_request)

      assert_response :success
      assert_select "h3", text: /Commits on/
      assert_select "[data-role='commit-list-item']", text: /Add widget/
      assert_select "[data-role='commit-list-item']", text: /Refine widget/

      get pull_request_commit_path(pull_request, fixture.feature_commits[:refine_widget])

      assert_response :success
      assert_select ".pf-page--wide"
      assert_select "h1", text: "feature"
      assert_select "[data-role='commit-summary']", text: /Refine widget/
      assert_select "[data-role='file-tree']", text: /app/
      assert_select "[data-role='file-tree']", text: /models/
      assert_select "[data-role='file-tree']", text: /widget\.rb/
      assert_select "form[action='#{pull_request_inline_comments_path(pull_request)}']"
      assert_select "[data-role='comment-trigger']"
      assert_select "[data-role='comment-menu']"
    end
  end

  test "adds an inline comment to a commit diff line" do
    with_sample_repository do |fixture|
      repository = create_local_repository!(fixture)
      pull_request = PullRequest.create!(local_repository: repository, source_branch: "feature", base_branch: "main")

      post pull_request_inline_comments_path(pull_request), params: {
        inline_comment: {
          commit_sha: fixture.feature_commits[:refine_widget],
          path: "app/models/widget.rb",
          side: "right",
          line_number: 3,
          body: "This is the version we should ship."
        },
        redirect_to: pull_request_commit_path(pull_request, fixture.feature_commits[:refine_widget])
      }

      assert_redirected_to pull_request_commit_path(pull_request, fixture.feature_commits[:refine_widget])
      follow_redirect!
      assert_select "[data-role='inline-comment']", text: /This is the version we should ship\./
    end
  end
end
