require "test_helper"

class PullRequestsFlowTest < ActionDispatch::IntegrationTest
  test "creates a local pull request from a branch comparison" do
    with_sample_repository do |fixture|
      repository = create_local_repository!(fixture)
      get repository_pull_requests_path(repository)

      assert_response :success
      assert_select "form[action='#{repository_pull_requests_path(repository)}']"
      assert_select "select[name='pull_request[source_branch]'] option", text: "feature"
      assert_select "select[name='pull_request[base_branch]'] option[selected='selected']", text: "main"

      post repository_pull_requests_path(repository), params: {
        pull_request: {
          source_branch: "feature",
          description: "Review the widget work."
        }
      }

      pull_request = PullRequest.order(:created_at).last

      assert_redirected_to repository_pull_request_path(repository, pull_request)
      follow_redirect!
      assert_response :success
      assert_select "h1", text: "feature"
      assert_select "a", text: "Conversation"
      assert_select "a", text: "Commits"
      assert_select "a", text: "Files changed"
      assert_select "[data-role='branch-pill']", text: "main"
      assert_select "[data-role='branch-pill']", text: "feature"
      assert_select "textarea[name='pull_request[description]']", text: "Review the widget work."
      assert_select "[data-role='pr-summary']", text: /2 commits/

      get repository_pull_request_path(repository, pull_request, tab: "files")
      assert_select "[data-role='changed-file']", text: /README.md/
      assert_select "[data-role='changed-file']", text: /app\/models\/widget.rb/
    end
  end

  test "defaults the compare branch away from the base branch when current branch is main" do
    with_sample_repository do |fixture|
      fixture.git("checkout", "main")
      repository = create_local_repository!(fixture)

      get repository_pull_requests_path(repository)

      assert_response :success
      assert_select "select[name='pull_request[base_branch]'] option[selected='selected']", text: "main"
      assert_select "select[name='pull_request[source_branch]'] option[selected='selected']", text: "feature"
    end
  end

  test "updates the pull request description" do
    with_sample_repository do |fixture|
      repository = create_local_repository!(fixture)
      pull_request = PullRequest.create!(local_repository: repository, source_branch: "feature", base_branch: "main", description: "Draft")

      patch repository_pull_request_path(repository, pull_request), params: {
        pull_request: {
          base_branch: "main",
          description: "Ready to merge once the widget lands."
        }
      }

      assert_redirected_to repository_pull_request_path(repository, pull_request)
      assert_equal "Ready to merge once the widget lands.", pull_request.reload.description
    end
  end
end
