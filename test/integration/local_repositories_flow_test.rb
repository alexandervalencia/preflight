require "test_helper"

class LocalRepositoriesFlowTest < ActionDispatch::IntegrationTest
  test "browses local directories to add a repository" do
    with_sample_repository do |fixture|
      get browse_path(directory: File.dirname(fixture.path))

      assert_response :redirect
      follow_redirect!

      assert_response :success
      assert_select "h1", text: "Add repository"
      assert_select "form[action='#{repositories_path}'] input[value='#{fixture.path}']"
      assert_select "button", text: "Add"
    end
  end

  test "registers a local repository path and lands on its compare page" do
    with_sample_repository do |fixture|
      get new_repository_path

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
      assert_select ".app-chrome__repo-name", text: repository.name
      assert_select "h1", text: "Pull requests"
      assert_select "a", text: "New pull request"
    end
  end
end
