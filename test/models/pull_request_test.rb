require "test_helper"

class PullRequestTest < ActiveSupport::TestCase
  test "defaults the title to the source branch" do
    with_sample_repository do |fixture|
      local_repository = create_local_repository!(fixture)
      pull_request = PullRequest.new(local_repository:, source_branch: "feature")

      assert pull_request.valid?
      assert_equal "feature", pull_request.title
    end
  end

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

  test "allows only one pull request per source branch in a repository" do
    with_sample_repository do |fixture|
      local_repository = create_local_repository!(fixture)
      PullRequest.create!(local_repository:, source_branch: "feature", base_branch: "main")

      pull_request = PullRequest.new(local_repository:, source_branch: "feature", base_branch: "release")

      assert_not pull_request.valid?
      assert_includes pull_request.errors[:source_branch], "already has an open local pull request"
    end
  end

  test "allows a new pull request for a branch after the previous one is closed" do
    with_sample_repository do |fixture|
      local_repository = create_local_repository!(fixture)
      existing = PullRequest.create!(local_repository:, source_branch: "feature", base_branch: "main")
      existing.update!(status: "closed")

      new_pr = PullRequest.new(local_repository:, source_branch: "feature", base_branch: "main")
      assert new_pr.valid?
    end
  end

  test "still prevents duplicate open pull requests for the same branch" do
    with_sample_repository do |fixture|
      local_repository = create_local_repository!(fixture)
      PullRequest.create!(local_repository:, source_branch: "feature", base_branch: "main")

      duplicate = PullRequest.new(local_repository:, source_branch: "feature", base_branch: "main")
      assert_not duplicate.valid?
      assert_includes duplicate.errors[:source_branch], "already has an open local pull request"
    end
  end

  test "defaults status to open" do
    with_sample_repository do |fixture|
      local_repository = create_local_repository!(fixture)
      pull_request = PullRequest.create!(local_repository:, source_branch: "feature", base_branch: "main")
      assert_equal "open", pull_request.status
    end
  end

  test "cleans up uploads directory when PR is destroyed" do
    with_sample_repository do |fixture|
      Dir.mktmpdir("preflight-uploads") do |uploads_dir|
        ENV["PREFLIGHT_UPLOADS_PATH"] = uploads_dir

        local_repository = create_local_repository!(fixture)
        pr = PullRequest.create!(local_repository:, source_branch: "feature", base_branch: "main")

        pr_uploads = File.join(uploads_dir, pr.id.to_s)
        FileUtils.mkdir_p(pr_uploads)
        File.write(File.join(pr_uploads, "test.png"), "fake")

        assert Dir.exist?(pr_uploads)

        pr.destroy!

        assert_not Dir.exist?(pr_uploads)
      ensure
        ENV.delete("PREFLIGHT_UPLOADS_PATH")
      end
    end
  end
end
