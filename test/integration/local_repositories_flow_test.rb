require "test_helper"

class LocalRepositoriesFlowTest < ActionDispatch::IntegrationTest
  test "browses local directories to add a repository" do
    with_sample_repository do |fixture|
      get browse_path(directory: File.dirname(fixture.path))

      assert_response :success
      assert_select "h1", text: "Browse local folders"
      assert_select "form[action='#{repositories_path}'] input[value='#{fixture.path}']"
      assert_select "button", text: /Add #{File.basename(fixture.path)}/
    end
  end

  test "registers a local repository path and lands on its compare page" do
    with_sample_repository do |fixture|
      get root_path

      assert_response :success
      assert_select "form[action='#{repositories_path}']"

      post repositories_path, params: {
        local_repository: {
          path: fixture.path
        }
      }

      repository = LocalRepository.order(:created_at).last

      assert_redirected_to repository_pulls_path(repository)
      follow_redirect!
      assert_response :success
      assert_select ".pf-repository-header__path", text: /#{Regexp.escape(repository.name)}/
      assert_select "h1", text: "Pull requests"
      assert_select "a", text: "New pull request"
    end
  end
end
