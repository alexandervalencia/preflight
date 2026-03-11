require "test_helper"

class GitRepositoryTest < ActiveSupport::TestCase
  test "lists local branches and resolves the default branch" do
    with_sample_repository do |fixture|
      repository = GitRepository.new(path: fixture.path)

      assert_equal "main", repository.default_branch
      assert_equal %w[feature main], repository.branches.map(&:name)
      assert_equal "feature", repository.current_branch
    end
  end

  test "builds a comparison with commits and parsed file diffs" do
    with_sample_repository do |fixture|
      comparison = GitRepository.new(path: fixture.path).compare(base: "main", head: "feature")

      assert_equal %w[Add\ widget Refine\ widget], comparison.commits.map(&:message)
      assert_equal ["README.md", "app/models/widget.rb"], comparison.files.map(&:path)

      widget_file = comparison.files.find { |file| file.path == "app/models/widget.rb" }

      assert_equal "A", widget_file.status
      assert_includes widget_file.lines.map(&:type), :hunk
      assert_includes widget_file.lines.map(&:content), "+class Widget"
      assert_includes widget_file.lines.map(&:content), "+    :ready"
    end
  end

  test "returns commit details for an individual feature commit" do
    with_sample_repository do |fixture|
      commit = GitRepository.new(path: fixture.path).commit(fixture.feature_commits[:refine_widget])

      assert_equal "Refine widget", commit.message
      assert_equal fixture.feature_commits[:refine_widget], commit.sha
      assert_equal ["app/models/widget.rb"], commit.files.map(&:path)
    end
  end
end
