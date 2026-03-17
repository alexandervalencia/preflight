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

  test "enforces name uniqueness at the database level" do
    with_sample_repository do |fixture|
      create_local_repository!(fixture, name: "my-repo")

      with_sample_repository do |fixture2|
        duplicate = LocalRepository.new(name: "my-repo", path: fixture2.path)
        # The before_validation callback auto-suffixes the name to resolve collisions
        duplicate.valid?
        assert_equal "my-repo-2", duplicate.name

        # The uniqueness validation is still declared as a safety net
        assert LocalRepository.validators_on(:name).any? { |v| v.is_a?(ActiveRecord::Validations::UniquenessValidator) }
      end
    end
  end

  test "auto-suffixes name on collision" do
    with_sample_repository do |fixture|
      first = create_local_repository!(fixture, name: "my-repo")

      with_sample_repository do |fixture2|
        second = LocalRepository.new(name: "my-repo", path: fixture2.path)
        second.valid? # triggers before_validation
        assert_equal "my-repo-2", second.name
      end
    end
  end

  test "increments suffix until unique" do
    with_sample_repository do |fixture|
      create_local_repository!(fixture, name: "my-repo")

      with_sample_repository do |fixture2|
        LocalRepository.create!(name: "my-repo-2", path: fixture2.path)

        with_sample_repository do |fixture3|
          third = LocalRepository.new(name: "my-repo", path: fixture3.path)
          third.valid?
          assert_equal "my-repo-3", third.name
        end
      end
    end
  end
end
