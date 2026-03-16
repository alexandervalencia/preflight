require "test_helper"

class PullRequestFileReviewTest < ActionDispatch::IntegrationTest
  test "marks files as viewed and highlights new changes after another commit" do
    with_sample_repository do |fixture|
      repository = create_local_repository!(fixture)
      pull_request = PullRequest.create!(local_repository: repository, source_branch: "feature", base_branch: "main")

      post repository_pull_viewed_files_path(repository, pull_request), params: {
        path: "app/models/widget.rb",
        redirect_to: repository_pull_files_path(repository, pull_request)
      }

      assert_redirected_to repository_pull_files_path(repository, pull_request)
      follow_redirect!
      assert_select "[data-path='app/models/widget.rb'] .pf-view-toggle--checked", text: /Viewed/

      fixture.commit_file(
        branch: "feature",
        path: "app/models/widget.rb",
        content: "class Widget\n  def call\n    :shipped\n  end\nend\n",
        message: "Ship widget"
      )

      get repository_pull_files_path(repository, pull_request)

      assert_select "[data-path='app/models/widget.rb'] .pf-view-toggle--checked", count: 0
      assert_select "[data-path='app/models/widget.rb'] .pf-view-toggle", text: /Viewed/
    end
  end

  test "unchecks a viewed file" do
    with_sample_repository do |fixture|
      repository = create_local_repository!(fixture)
      pull_request = PullRequest.create!(local_repository: repository, source_branch: "feature", base_branch: "main")

      post repository_pull_viewed_files_path(repository, pull_request), params: {
        path: "app/models/widget.rb",
        viewed: "1",
        redirect_to: repository_pull_files_path(repository, pull_request)
      }

      post repository_pull_viewed_files_path(repository, pull_request), params: {
        path: "app/models/widget.rb",
        viewed: "0",
        redirect_to: repository_pull_files_path(repository, pull_request)
      }

      assert_redirected_to repository_pull_files_path(repository, pull_request)
      follow_redirect!
      assert_select "[data-path='app/models/widget.rb'] .pf-view-toggle--checked", count: 0
      assert_select "[data-path='app/models/widget.rb'] .pf-view-toggle", text: /Viewed/
    end
  end
end
