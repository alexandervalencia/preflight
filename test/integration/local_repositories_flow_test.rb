require "test_helper"

class LocalRepositoriesFlowTest < ActionDispatch::IntegrationTest
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

      assert_redirected_to repository_pull_requests_path(repository)
      follow_redirect!
      assert_response :success
      assert_select "h1", text: repository.name
      assert_select "form[action='#{repository_pull_requests_path(repository)}']"
    end
  end
end
