require "fileutils"
require "open3"

module GitFixtureHelper
  RepositoryFixture = Data.define(:path, :feature_head, :feature_commits) do
    def git(*args)
      stdout, stderr, status = Open3.capture3("git", *args, chdir: path)
      raise "git #{args.join(' ')} failed: #{stderr}" unless status.success?

      stdout.strip
    end

    def commit_file(branch:, path:, content:, message:)
      git("checkout", branch)
      absolute_path = File.join(self.path, path)
      FileUtils.mkdir_p(File.dirname(absolute_path))
      File.write(absolute_path, content)
      git("add", path)
      git("commit", "-m", message)
      git("rev-parse", "HEAD")
    end
  end

  def with_sample_repository
    Dir.mktmpdir("preflight-repo") do |directory|
      run_git(directory, "init", "-b", "main")
      run_git(directory, "config", "user.name", "Preflight Tests")
      run_git(directory, "config", "user.email", "preflight@example.com")
      run_git(directory, "config", "commit.gpgsign", "false")
      run_git(directory, "config", "core.hooksPath", "/dev/null")

      FileUtils.mkdir_p(File.join(directory, "app/models"))
      File.write(File.join(directory, "README.md"), "# Sample Repo\n")
      run_git(directory, "add", ".")
      run_git(directory, "commit", "-m", "Initial commit")

      run_git(directory, "checkout", "-b", "feature")
      File.write(File.join(directory, "README.md"), "# Sample Repo\n\nFeature branch notes.\n")
      File.write(File.join(directory, "app/models/widget.rb"), "class Widget\n  def call\n    :draft\n  end\nend\n")
      run_git(directory, "add", ".")
      run_git(directory, "commit", "-m", "Add widget")
      add_widget_sha = run_git(directory, "rev-parse", "HEAD")

      File.write(File.join(directory, "app/models/widget.rb"), "class Widget\n  def call\n    :ready\n  end\nend\n")
      run_git(directory, "add", "app/models/widget.rb")
      run_git(directory, "commit", "-m", "Refine widget")
      refine_widget_sha = run_git(directory, "rev-parse", "HEAD")

      yield RepositoryFixture.new(
        path: directory,
        feature_head: refine_widget_sha,
        feature_commits: {
          add_widget: add_widget_sha,
          refine_widget: refine_widget_sha
        }
      )
    end
  end

  def create_local_repository!(fixture, name: nil)
    LocalRepository.create!(name: name, path: fixture.path)
  end

  private

  def run_git(directory, *args)
    stdout, stderr, status = Open3.capture3("git", *args, chdir: directory)
    raise "git #{args.join(' ')} failed: #{stderr}" unless status.success?

    stdout.strip
  end
end

class ActiveSupport::TestCase
  include GitFixtureHelper
end
