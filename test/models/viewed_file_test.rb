require "test_helper"

class ViewedFileTest < ActiveSupport::TestCase
  test "marks a file outdated when newer commits change it" do
    with_sample_repository do |fixture|
      repository = create_local_repository!(fixture)
      pull_request = PullRequest.create!(local_repository: repository, source_branch: "feature", base_branch: "main")
      viewed_file = pull_request.viewed_files.create!(
        path: "app/models/widget.rb",
        last_viewed_commit_sha: fixture.feature_head
      )

      assert_predicate viewed_file, :current?

      new_head = fixture.commit_file(
        branch: "feature",
        path: "app/models/widget.rb",
        content: "class Widget\n  def call\n    :shipped\n  end\nend\n",
        message: "Ship widget"
      )

      assert_equal new_head, pull_request.reload.head_sha
      assert_not viewed_file.reload.current?
    end
  end
end
