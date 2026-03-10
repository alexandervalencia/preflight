require "test_helper"

class PullRequestReviewTest < ActionDispatch::IntegrationTest
  test "adds an inline comment on the overall pull request diff" do
    with_sample_repository do |fixture|
      with_preflight_repository_path(fixture.path) do
        pull_request = PullRequest.create!(source_branch: "feature", base_branch: "main")

        post pull_request_inline_comments_path(pull_request), params: {
          inline_comment: {
            path: "app/models/widget.rb",
            side: "right",
            line_number: 3,
            body: "Ship this from the PR view."
          },
          redirect_to: pull_request_path(pull_request)
        }

        assert_redirected_to pull_request_path(pull_request)
        follow_redirect!
        assert_select "[data-role='inline-comment']", text: /Ship this from the PR view\./
      end
    end
  end

  test "steps through commits and adds an inline comment to a diff line" do
    with_sample_repository do |fixture|
      with_preflight_repository_path(fixture.path) do
        pull_request = PullRequest.create!(source_branch: "feature", base_branch: "main")

        get pull_request_path(pull_request)
        assert_select "a[href='#{pull_request_commit_path(pull_request, fixture.feature_commits[:add_widget])}']", text: /Add widget/
        assert_select "a[href='#{pull_request_commit_path(pull_request, fixture.feature_commits[:refine_widget])}']", text: /Refine widget/

        get pull_request_commit_path(pull_request, fixture.feature_commits[:refine_widget])

        assert_response :success
        assert_select "h1", text: "Refine widget"
        assert_select "a[href='#{pull_request_commit_path(pull_request, fixture.feature_commits[:add_widget])}']", text: /Previous/
        assert_select "form[action='#{pull_request_inline_comments_path(pull_request)}']"

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
end
