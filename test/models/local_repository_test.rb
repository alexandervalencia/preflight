require "test_helper"

class LocalRepositoryTest < ActiveSupport::TestCase
  test "defaults the name from the repository folder" do
    with_sample_repository do |fixture|
      repository = LocalRepository.new(path: fixture.path)

      assert repository.valid?
      assert_equal File.basename(fixture.path), repository.name
    end
  end

  test "requires the path to point at a git repository" do
    Dir.mktmpdir("plain-folder") do |directory|
      repository = LocalRepository.new(path: directory)

      assert_not repository.valid?
      assert_includes repository.errors[:path], "must point to a local git repository"
    end
  end
end
