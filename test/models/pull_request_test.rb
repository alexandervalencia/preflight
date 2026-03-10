require "test_helper"

class PullRequestTest < ActiveSupport::TestCase
  test "defaults the base branch to the repository default branch" do
    with_sample_repository do |fixture|
      local_repository = create_local_repository!(fixture)
      pull_request = PullRequest.new(local_repository:, source_branch: "feature")

      assert pull_request.valid?
      assert_equal "main", pull_request.base_branch
    end
  end

  test "requires different source and base branches" do
    with_sample_repository do |fixture|
      local_repository = create_local_repository!(fixture)
      pull_request = PullRequest.new(local_repository:, source_branch: "main", base_branch: "main")

      assert_not pull_request.valid?
      assert_includes pull_request.errors[:base_branch], "must be different from the source branch"
    end
  end
end
