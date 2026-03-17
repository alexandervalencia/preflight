require "test_helper"

class UploadsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @original_uploads_path = ENV["PREFLIGHT_UPLOADS_PATH"]
    @uploads_dir = Dir.mktmpdir("preflight-uploads")
    ENV["PREFLIGHT_UPLOADS_PATH"] = @uploads_dir
  end

  teardown do
    ENV["PREFLIGHT_UPLOADS_PATH"] = @original_uploads_path
    FileUtils.rm_rf(@uploads_dir) if @uploads_dir
  end

  test "POST upload saves image and returns markdown reference" do
    with_sample_repository do |fixture|
      local_repository = create_local_repository!(fixture)
      pull_request = PullRequest.create!(
        local_repository:, source_branch: "feature", base_branch: "main"
      )

      image = fixture_file_upload("test/fixtures/files/test_image.png", "image/png")

      post repository_pull_uploads_path(local_repository, pull_request), params: { file: image }

      assert_response :created
      body = response.parsed_body
      assert body["markdown"].include?("![test_image.png]")
      assert body["url"].include?("/_preflight/uploads/")
    end
  end

  test "POST upload rejects non-image files" do
    with_sample_repository do |fixture|
      local_repository = create_local_repository!(fixture)
      pull_request = PullRequest.create!(
        local_repository:, source_branch: "feature", base_branch: "main"
      )

      file = fixture_file_upload("test/fixtures/files/test_file.txt", "text/plain")

      post repository_pull_uploads_path(local_repository, pull_request), params: { file: file }

      assert_response :unprocessable_entity
    end
  end

  test "POST upload rejects files over 10MB" do
    with_sample_repository do |fixture|
      local_repository = create_local_repository!(fixture)
      pull_request = PullRequest.create!(
        local_repository:, source_branch: "feature", base_branch: "main"
      )

      image = fixture_file_upload("test/fixtures/files/test_image.png", "image/png")

      # Temporarily lower the max size so our tiny test image exceeds it
      original_max = UploadsController::MAX_SIZE
      UploadsController.send(:remove_const, :MAX_SIZE)
      UploadsController.const_set(:MAX_SIZE, 1) # 1 byte

      post repository_pull_uploads_path(local_repository, pull_request), params: { file: image }
      assert_response :unprocessable_entity
    ensure
      UploadsController.send(:remove_const, :MAX_SIZE)
      UploadsController.const_set(:MAX_SIZE, original_max)
    end
  end

  test "GET serving route returns uploaded image" do
    with_sample_repository do |fixture|
      local_repository = create_local_repository!(fixture)
      pull_request = PullRequest.create!(
        local_repository:, source_branch: "feature", base_branch: "main"
      )

      # Manually place a file in the uploads directory
      pr_dir = File.join(@uploads_dir, pull_request.id.to_s)
      FileUtils.mkdir_p(pr_dir)
      File.write(File.join(pr_dir, "test.png"), "fake png content")

      get preflight_upload_path(pull_request_id: pull_request.id, filename: "test.png")

      assert_response :success
    end
  end
end
