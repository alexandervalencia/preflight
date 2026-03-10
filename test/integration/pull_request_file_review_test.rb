require "test_helper"

class PullRequestFileReviewTest < ActionDispatch::IntegrationTest
  test "marks files as viewed and highlights new changes after another commit" do
    with_sample_repository do |fixture|
      repository = create_local_repository!(fixture)
      pull_request = PullRequest.create!(local_repository: repository, source_branch: "feature", base_branch: "main")

      post pull_request_viewed_files_path(pull_request), params: {
        path: "app/models/widget.rb",
        redirect_to: repository_pull_request_path(repository, pull_request, tab: "files")
      }

      assert_redirected_to repository_pull_request_path(repository, pull_request, tab: "files")
      follow_redirect!
      assert_select "[data-path='app/models/widget.rb'] [data-role='view-state']", text: "Viewed"

      fixture.commit_file(
        branch: "feature",
        path: "app/models/widget.rb",
        content: "class Widget\n  def call\n    :shipped\n  end\nend\n",
        message: "Ship widget"
      )

      get repository_pull_request_path(repository, pull_request, tab: "files")

      assert_select "[data-path='app/models/widget.rb'] [data-role='view-state']", text: "New changes"
    end
  end
end
