require "test_helper"

class Api::PullRequestsControllerTest < ActionDispatch::IntegrationTest
  test "GET /api/status returns ok" do
    get api_status_path
    assert_response :success
    assert_equal "ok", response.parsed_body["status"]
  end

  test "POST /api/pull_requests creates a new PR and returns URL" do
    with_sample_repository do |fixture|
      post api_pull_requests_path, params: {
        repo_path: fixture.path,
        source_branch: "feature",
        base_branch: "main"
      }, as: :json

      assert_response :created
      body = response.parsed_body
      assert body["url"].present?
      assert body["url"].start_with?("/")
      assert body["repository_name"].present?

      pr = PullRequest.last
      assert_equal "feature", pr.source_branch
      assert_equal "main", pr.base_branch
      assert_equal "open", pr.status
    end
  end

  test "POST /api/pull_requests auto-registers unknown repository" do
    with_sample_repository do |fixture|
      assert_difference "LocalRepository.count", 1 do
        post api_pull_requests_path, params: {
          repo_path: fixture.path,
          source_branch: "feature",
          base_branch: "main"
        }, as: :json
      end

      assert_response :created
    end
  end

  test "POST /api/pull_requests returns existing open PR for same branch" do
    with_sample_repository do |fixture|
      local_repository = create_local_repository!(fixture)
      existing = PullRequest.create!(
        local_repository:, source_branch: "feature", base_branch: "main"
      )

      post api_pull_requests_path, params: {
        repo_path: fixture.path,
        source_branch: "feature",
        base_branch: "main"
      }, as: :json

      assert_response :ok
      assert_includes response.parsed_body["url"], existing.id.to_s
    end
  end

  test "POST /api/pull_requests accepts title and description" do
    with_sample_repository do |fixture|
      post api_pull_requests_path, params: {
        repo_path: fixture.path,
        source_branch: "feature",
        base_branch: "main",
        title: "Add login page",
        description: "Implements the new login flow with OAuth support."
      }, as: :json

      assert_response :created

      pr = PullRequest.last
      assert_equal "Add login page", pr.title
      assert_equal "Implements the new login flow with OAuth support.", pr.description
    end
  end

  test "POST /api/pull_requests uses defaults when title and description omitted" do
    with_sample_repository do |fixture|
      post api_pull_requests_path, params: {
        repo_path: fixture.path,
        source_branch: "feature",
        base_branch: "main"
      }, as: :json

      assert_response :created

      pr = PullRequest.last
      assert_equal "feature", pr.title
      assert_equal "", pr.description
    end
  end

  test "POST /api/pull_requests errors when on base branch" do
    with_sample_repository do |fixture|
      post api_pull_requests_path, params: {
        repo_path: fixture.path,
        source_branch: "main",
        base_branch: "main"
      }, as: :json

      assert_response :unprocessable_entity
    end
  end
end
