require "test_helper"

class PullRequestFileReviewTest < ActionDispatch::IntegrationTest
  test "marks files as viewed and highlights new changes after another commit" do
    with_sample_repository do |fixture|
      with_preflight_repository_path(fixture.path) do
        pull_request = PullRequest.create!(source_branch: "feature", base_branch: "main")

        post pull_request_viewed_files_path(pull_request), params: {
          path: "app/models/widget.rb"
        }

        assert_redirected_to pull_request_path(pull_request)
        follow_redirect!
        assert_select "[data-path='app/models/widget.rb'] [data-role='view-state']", text: "Viewed"

        fixture.commit_file(
          branch: "feature",
          path: "app/models/widget.rb",
          content: "class Widget\n  def call\n    :shipped\n  end\nend\n",
          message: "Ship widget"
        )

        get pull_request_path(pull_request)

        assert_select "[data-path='app/models/widget.rb'] [data-role='view-state']", text: "New changes"
      end
    end
  end
end
