# Preflight CLI & GitHub Export Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Transform preflight into an installable CLI tool with `preflight push` workflow, image uploads, GitHub PR export, and Homebrew distribution.

**Architecture:** Go CLI binary manages a Rails server (with bundled Ruby) via PID file and HTTP API. The CLI handles terminal commands; the server handles the browser UI and git operations. Data lives in `~/.preflight/`.

**Tech Stack:** Rails 8.1 (existing), Go (CLI), SQLite, Stimulus (image uploads), `gh` CLI (GitHub export)

**Spec:** `docs/superpowers/specs/2026-03-16-preflight-cli-and-github-export-design.md`

---

## File Structure

### New Files

| File | Responsibility |
|------|---------------|
| `db/migrate/XXXXXXXX_add_status_and_github_url_to_pull_requests.rb` | Add status + github_pr_url columns, change unique index to partial |
| `db/migrate/XXXXXXXX_add_unique_index_on_local_repository_name.rb` | Add unique index on local_repositories.name |
| `app/controllers/api/pull_requests_controller.rb` | JSON API for CLI: create PR, health check |
| `app/controllers/uploads_controller.rb` | Image upload + serving |
| `app/controllers/github_exports_controller.rb` | GitHub PR creation via `gh` |
| `app/services/github_cli.rb` | Wraps `gh` CLI interactions |
| `app/middleware/idle_shutdown.rb` | Tracks last request time for auto-shutdown |
| `config/initializers/idle_shutdown.rb` | Starts background shutdown-check thread |
| `app/javascript/controllers/image_upload_controller.js` | Stimulus controller for drag-and-drop image upload |
| `test/models/local_repository_test.rb` | Tests for name uniqueness and auto-suffix |
| `test/controllers/api/pull_requests_controller_test.rb` | Tests for API endpoints |
| `test/controllers/uploads_controller_test.rb` | Tests for image upload and serving |
| `test/controllers/github_exports_controller_test.rb` | Tests for GitHub export |
| `test/services/github_cli_test.rb` | Tests for GithubCli service |
| `cli/` | Go CLI module (separate directory in repo) |
| `cli/main.go` | CLI entry point |
| `cli/cmd/root.go` | Cobra root command |
| `cli/cmd/push.go` | `preflight push` command |
| `cli/cmd/open.go` | `preflight open` command |
| `cli/cmd/list.go` | `preflight list` command |
| `cli/cmd/server.go` | `preflight server start/stop/restart` commands |
| `cli/internal/server/manager.go` | Server process lifecycle (start, stop, health check) |
| `cli/internal/server/api.go` | HTTP API client for talking to the Rails server |
| `cli/internal/git/repo.go` | Git operations (current branch, repo path, default branch) |
| `cli/internal/db/queries.go` | Direct SQLite reads for `list` command |
| `cli/internal/config/paths.go` | `~/.preflight/` path constants |

### Modified Files

| File | Change |
|------|--------|
| `app/models/pull_request.rb` | Add status scoping to uniqueness validation, add `open`/`closed` scopes |
| `app/models/local_repository.rb` | Add name uniqueness validation, auto-suffix logic |
| `app/controllers/pull_requests_controller.rb` | Scope `existing_pull_request_for` to open PRs, extract shared creation logic |
| `app/views/pull_requests/show.html.erb` | Add image upload zone, GitHub export button, closed state |
| `app/views/pull_requests/index.html.erb` | Add open/closed filter tabs |
| `config/routes.rb` | Add API routes, upload routes, GitHub export route |
| `config/database.yml` | Support `PREFLIGHT_DB_PATH` env var |
| `config/puma.rb` | Add idle shutdown middleware, PID file support |
| `app/helpers/markdown_helper.rb` | Support rendering uploaded image markdown |
| `test/models/pull_request_test.rb` | Update uniqueness test for status scoping |
| `test/test_helper.rb` | Add helpers for API testing |

---

## Chunk 1: Database & Model Foundation

### Task 1: Add status and github_pr_url columns to pull_requests

**Files:**
- Create: `db/migrate/XXXXXXXX_add_status_and_github_url_to_pull_requests.rb`
- Modify: `db/schema.rb` (auto-generated)

- [ ] **Step 1: Generate the migration**

```bash
devbox run -- bin/rails generate migration AddStatusAndGithubUrlToPullRequests status:string github_pr_url:string
```

- [ ] **Step 2: Edit the migration to add default, partial index, and remove old index**

Replace the generated migration body with:

```ruby
class AddStatusAndGithubUrlToPullRequests < ActiveRecord::Migration[8.1]
  def change
    add_column :pull_requests, :status, :string, default: "open", null: false
    add_column :pull_requests, :github_pr_url, :string

    remove_index :pull_requests, name: "index_pull_requests_on_repository_and_source_branch"
    add_index :pull_requests, [:local_repository_id, :source_branch],
      unique: true,
      where: "status = 'open'",
      name: "index_pull_requests_on_repo_and_branch_when_open"
  end
end
```

- [ ] **Step 3: Run the migration**

```bash
devbox run -- bin/rails db:migrate
```

Expected: migration runs successfully, `db/schema.rb` updated with new columns and partial index.

- [ ] **Step 4: Verify schema**

Check `db/schema.rb` shows:
- `t.string "status", default: "open", null: false`
- `t.string "github_pr_url"`
- Partial unique index with `where: "status = 'open'"`

- [ ] **Step 5: Commit**

```bash
git add db/migrate/*_add_status_and_github_url_to_pull_requests.rb db/schema.rb
git commit -m "add status and github_pr_url columns to pull_requests"
```

### Task 2: Add unique index on local_repositories.name

**Files:**
- Create: `db/migrate/XXXXXXXX_add_unique_index_on_local_repository_name.rb`
- Modify: `db/schema.rb` (auto-generated)

- [ ] **Step 1: Generate the migration**

```bash
devbox run -- bin/rails generate migration AddUniqueIndexOnLocalRepositoryName
```

- [ ] **Step 2: Edit the migration**

```ruby
class AddUniqueIndexOnLocalRepositoryName < ActiveRecord::Migration[8.1]
  def change
    add_index :local_repositories, :name, unique: true
  end
end
```

- [ ] **Step 3: Run the migration**

```bash
devbox run -- bin/rails db:migrate
```

- [ ] **Step 4: Commit**

```bash
git add db/migrate/*_add_unique_index_on_local_repository_name.rb db/schema.rb
git commit -m "add unique index on local_repositories.name"
```

### Task 3: Update PullRequest model with status scoping

**Files:**
- Modify: `app/models/pull_request.rb`
- Modify: `test/models/pull_request_test.rb`

- [ ] **Step 1: Write the failing test for status-scoped uniqueness**

Add to `test/models/pull_request_test.rb`:

```ruby
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
```

- [ ] **Step 2: Run tests to verify they fail**

```bash
devbox run -- bin/rails test test/models/pull_request_test.rb
```

Expected: the "allows new PR after closed" test fails because the uniqueness validation isn't scoped to status yet.

- [ ] **Step 3: Update PullRequest model**

In `app/models/pull_request.rb`, change the uniqueness validation (lines 8-11):

```ruby
validates :source_branch, uniqueness: {
  scope: :local_repository_id,
  conditions: -> { where(status: "open") },
  message: "already has an open local pull request"
}
```

Add scopes after the validations:

```ruby
scope :open, -> { where(status: "open") }
scope :closed, -> { where(status: "closed") }
```

- [ ] **Step 4: Run tests to verify they pass**

```bash
devbox run -- bin/rails test test/models/pull_request_test.rb
```

Expected: all tests pass.

- [ ] **Step 5: Commit**

```bash
git add app/models/pull_request.rb test/models/pull_request_test.rb
git commit -m "scope PR uniqueness validation to open status"
```

### Task 4: Update LocalRepository model with name uniqueness and auto-suffix

**Files:**
- Modify: `app/models/local_repository.rb`
- Create: `test/models/local_repository_test.rb`

- [ ] **Step 1: Write failing tests**

Create `test/models/local_repository_test.rb`:

```ruby
require "test_helper"

class LocalRepositoryTest < ActiveSupport::TestCase
  test "validates name uniqueness" do
    with_sample_repository do |fixture|
      create_local_repository!(fixture, name: "my-repo")

      duplicate = LocalRepository.new(name: "my-repo", path: "/nonexistent")
      assert_not duplicate.valid?
      assert_includes duplicate.errors[:name], "has already been taken"
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
```

- [ ] **Step 2: Run tests to verify they fail**

```bash
devbox run -- bin/rails test test/models/local_repository_test.rb
```

- [ ] **Step 3: Update LocalRepository model**

In `app/models/local_repository.rb`, add name uniqueness validation:

```ruby
validates :name, presence: true, uniqueness: true
```

Update the `assign_name` callback to handle collisions:

```ruby
def assign_name
  self.name = File.basename(path) if name.blank? && path.present?
  resolve_name_collision if name.present?
end

def resolve_name_collision
  return unless LocalRepository.where(name: name).where.not(id: id).exists?

  base_name = name
  counter = 2
  loop do
    candidate = "#{base_name}-#{counter}"
    unless LocalRepository.where(name: candidate).where.not(id: id).exists?
      self.name = candidate
      break
    end
    counter += 1
  end
end
```

- [ ] **Step 4: Run tests to verify they pass**

```bash
devbox run -- bin/rails test test/models/local_repository_test.rb
```

- [ ] **Step 5: Run full test suite**

```bash
devbox run -- bin/rails test
```

Expected: all tests pass.

- [ ] **Step 6: Commit**

```bash
git add app/models/local_repository.rb test/models/local_repository_test.rb
git commit -m "add name uniqueness validation with auto-suffix on collision"
```

### Task 5: Update existing queries to scope to open PRs

**Files:**
- Modify: `app/controllers/pull_requests_controller.rb`
- Modify: `app/views/pull_requests/index.html.erb`

- [ ] **Step 1: Update the controller**

In `app/controllers/pull_requests_controller.rb`:

Update `index` (line 7):
```ruby
def index
  @pull_requests = @local_repository.pull_requests.open.order(created_at: :desc)
end
```

Update `existing_pull_request_for` (lines 79-83):
```ruby
def existing_pull_request_for(source_branch)
  return if source_branch.blank?

  @local_repository.pull_requests.open.find_by(source_branch:)
end
```

- [ ] **Step 2: Run full test suite**

```bash
devbox run -- bin/rails test
```

Expected: all tests pass.

- [ ] **Step 3: Commit**

```bash
git add app/controllers/pull_requests_controller.rb
git commit -m "scope PR queries to open status"
```

### Task 6: Configurable database path

**Files:**
- Modify: `config/database.yml`

- [ ] **Step 1: Update database.yml to support PREFLIGHT_DB_PATH**

Change the development and production sections:

```yaml
development:
  <<: *default
  database: <%= ENV.fetch("PREFLIGHT_DB_PATH", "storage/development.sqlite3") %>

production:
  primary:
    <<: *default
    database: <%= ENV.fetch("PREFLIGHT_DB_PATH", "storage/production.sqlite3") %>
```

Leave test unchanged (tests should always use their own DB). The CLI server runs in production mode, so it needs `PREFLIGHT_DB_PATH` support there too.

- [ ] **Step 2: Verify the app still boots**

```bash
devbox run -- bin/rails runner "puts ActiveRecord::Base.connection.adapter_name"
```

Expected: prints "SQLite"

- [ ] **Step 3: Commit**

```bash
git add config/database.yml
git commit -m "support PREFLIGHT_DB_PATH env var for database location"
```

---

## Chunk 2: API Endpoints & Server Lifecycle

### Task 7: Add API routes

**Files:**
- Modify: `config/routes.rb`

- [ ] **Step 1: Add API routes to routes.rb**

Add before the closing `end`:

```ruby
namespace :api do
  resources :pull_requests, only: [:create, :index]
  get "status", to: "pull_requests#status"
end
```

- [ ] **Step 2: Verify routes compile**

```bash
devbox run -- bin/rails routes | grep api
```

Expected: shows `POST /api/pull_requests` and `GET /api/status`

- [ ] **Step 3: Commit**

```bash
git add config/routes.rb
git commit -m "add API routes for CLI communication"
```

### Task 8: Create Api::PullRequestsController

**Files:**
- Create: `app/controllers/api/pull_requests_controller.rb`
- Create: `test/controllers/api/pull_requests_controller_test.rb`

- [ ] **Step 1: Write failing test for health check**

Create `test/controllers/api/pull_requests_controller_test.rb`:

```ruby
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
      assert body["url"].start_with?("/")  # Returns a path, not full URL
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
```

- [ ] **Step 2: Run tests to verify they fail**

```bash
devbox run -- bin/rails test test/controllers/api/pull_requests_controller_test.rb
```

- [ ] **Step 3: Create the api directory and controller**

```bash
mkdir -p app/controllers/api
```

Create `app/controllers/api/pull_requests_controller.rb`:

```ruby
class Api::PullRequestsController < ApplicationController
  skip_forgery_protection

  # Use path helpers (not URL helpers) — the CLI knows the host already
  def status
    render json: { status: "ok" }
  end

  def index
    repo = LocalRepository.find_by(path: params[:repo_path])
    return head :not_found unless repo

    pr = repo.pull_requests.open.find_by(source_branch: params[:source_branch])
    return head :not_found unless pr

    render json: {
      url: pull_request_path_for(repo, pr),
      repository_name: repo.name,
      pull_request_id: pr.id
    }
  end

  def create
    repo_path = params[:repo_path]
    source_branch = params[:source_branch]
    base_branch = params[:base_branch]

    local_repository = LocalRepository.find_by(path: repo_path) || register_repository(repo_path)
    return render_error("Repository could not be registered") unless local_repository&.persisted?

    existing = local_repository.pull_requests.open.find_by(source_branch:)
    if existing
      return render json: {
        url: pull_request_path_for(local_repository, existing),
        repository_name: local_repository.name,
        pull_request_id: existing.id,
        created: false
      }, status: :ok
    end

    pull_request = local_repository.pull_requests.new(
      source_branch:,
      base_branch: base_branch.presence || local_repository.default_branch
    )

    if pull_request.save
      render json: {
        url: pull_request_path_for(local_repository, pull_request),
        repository_name: local_repository.name,
        pull_request_id: pull_request.id,
        created: true
      }, status: :created
    else
      render json: { errors: pull_request.errors.full_messages }, status: :unprocessable_entity
    end
  end

  private

  def register_repository(path)
    repo = LocalRepository.new(path:)
    repo.save ? repo : nil
  end

  def pull_request_path_for(repository, pull_request)
    repository_pull_path(repository, pull_request)
  end

  def render_error(message)
    render json: { errors: [message] }, status: :unprocessable_entity
  end
end
```

- [ ] **Step 4: Run tests to verify they pass**

```bash
devbox run -- bin/rails test test/controllers/api/pull_requests_controller_test.rb
```

- [ ] **Step 5: Run full test suite**

```bash
devbox run -- bin/rails test
```

- [ ] **Step 6: Commit**

```bash
git add app/controllers/api/pull_requests_controller.rb test/controllers/api/pull_requests_controller_test.rb
git commit -m "add API controller for CLI: create PR and health check"
```

### Task 9: Idle shutdown middleware and background thread

**Files:**
- Create: `app/middleware/idle_shutdown.rb`
- Create: `config/initializers/idle_shutdown.rb`
- Modify: `config/puma.rb`

- [ ] **Step 1: Create the middleware**

Create `app/middleware/idle_shutdown.rb`:

```ruby
class IdleShutdown
  @mutex = Mutex.new
  @last_request_at = Time.now

  def initialize(app)
    @app = app
  end

  def call(env)
    self.class.touch
    @app.call(env)
  end

  def self.touch
    @mutex.synchronize { @last_request_at = Time.now }
  end

  def self.last_request_at
    @mutex.synchronize { @last_request_at }
  end
end
```

- [ ] **Step 2: Create the initializer**

Create `config/initializers/idle_shutdown.rb`:

```ruby
if ENV["PREFLIGHT_IDLE_SHUTDOWN"].present?
  Rails.application.config.middleware.use IdleShutdown
end
```

Add idle shutdown thread to `config/puma.rb` (only runs when the web server boots, not during `rails runner` or `rails console`):

```ruby
# Add at the end of config/puma.rb:
if ENV["PREFLIGHT_IDLE_SHUTDOWN"].present?
  on_booted do
    timeout_minutes = ENV.fetch("PREFLIGHT_IDLE_TIMEOUT", "30").to_i

    Thread.new do
      loop do
        sleep 60
        elapsed = Time.now - IdleShutdown.last_request_at
        if elapsed >= timeout_minutes * 60
          Rails.logger.info "Preflight shutting down after #{timeout_minutes} minutes of inactivity"
          pid_path = ENV["PIDFILE"]
          FileUtils.rm_f(pid_path) if pid_path
          exit(0)
        end
      end
    end
  end
end
```

- [ ] **Step 3: Update puma.rb for PID file support**

The existing `config/puma.rb` already has `pidfile ENV["PIDFILE"] if ENV["PIDFILE"]` on line 39. No change needed.

- [ ] **Step 4: Verify the app boots with idle shutdown disabled (default)**

```bash
devbox run -- bin/rails runner "puts 'OK'"
```

Expected: prints "OK" without errors.

- [ ] **Step 5: Commit**

```bash
git add app/middleware/idle_shutdown.rb config/initializers/idle_shutdown.rb
git commit -m "add idle shutdown middleware with configurable timeout"
```

---

## Chunk 3: Image Upload Support

### Task 10: Add upload routes

**Files:**
- Modify: `config/routes.rb`

- [ ] **Step 1: Add upload and image serving routes**

In `config/routes.rb`, add these routes. The upload `create` route must go **outside** the `scope "/pull/:id", controller: "pull_requests"` block (since that scope forces the controller to `pull_requests`). Add it inside `scope "/:repository_name"` but after the pull_requests scopes:

```ruby
# Inside scope "/:repository_name", after the existing pull request scopes:
post "pull/:id/uploads", to: "uploads#create", as: :repository_pull_uploads
post "pull/:id/github_export", to: "github_exports#create", as: :repository_pull_github_export
```

Outside the `/:repository_name` scope entirely (before `namespace :api`), add the image serving route:

```ruby
get "/_preflight/uploads/:pull_request_id/:filename", to: "uploads#show", as: :preflight_upload,
  constraints: { filename: /[^\/]+/ }
```

- [ ] **Step 2: Verify routes**

```bash
devbox run -- bin/rails routes | grep upload
```

- [ ] **Step 3: Commit**

```bash
git add config/routes.rb
git commit -m "add routes for image upload and serving"
```

### Task 11: Create UploadsController

**Files:**
- Create: `app/controllers/uploads_controller.rb`
- Create: `test/controllers/uploads_controller_test.rb`

- [ ] **Step 1: Write failing tests**

Create `test/controllers/uploads_controller_test.rb`:

```ruby
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
      # Stub the size to exceed 10MB
      image.stub(:size, 11.megabytes) do
        post repository_pull_uploads_path(local_repository, pull_request), params: { file: image }
        assert_response :unprocessable_entity
      end
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
```

- [ ] **Step 2: Create test fixture files**

```bash
mkdir -p test/fixtures/files
# Create a minimal valid PNG (1x1 pixel)
printf '\x89PNG\r\n\x1a\n\x00\x00\x00\rIHDR\x00\x00\x00\x01\x00\x00\x00\x01\x08\x02\x00\x00\x00\x90wS\xde\x00\x00\x00\x0cIDATx\x9cc\xf8\x0f\x00\x00\x01\x01\x00\x05\x18\xd8N\x00\x00\x00\x00IEND\xaeB`\x82' > test/fixtures/files/test_image.png
echo "test content" > test/fixtures/files/test_file.txt
```

- [ ] **Step 3: Run tests to verify they fail**

```bash
devbox run -- bin/rails test test/controllers/uploads_controller_test.rb
```

- [ ] **Step 4: Create the controller**

Create `app/controllers/uploads_controller.rb`:

```ruby
class UploadsController < ApplicationController
  include RepositoryScoped

  skip_before_action :set_local_repository, only: :show
  skip_forgery_protection only: :create

  ALLOWED_TYPES = %w[image/png image/jpeg image/gif image/webp].freeze
  MAX_SIZE = 10.megabytes

  def create
    @pull_request = @local_repository.pull_requests.find(params[:id])
    file = params[:file]

    unless file.is_a?(ActionDispatch::Http::UploadedFile)
      return render json: { error: "No file provided" }, status: :unprocessable_entity
    end

    unless ALLOWED_TYPES.include?(file.content_type)
      return render json: { error: "File type not allowed. Use PNG, JPG, GIF, or WebP." }, status: :unprocessable_entity
    end

    if file.size > MAX_SIZE
      return render json: { error: "File too large. Maximum 10MB." }, status: :unprocessable_entity
    end

    filename = sanitize_filename(file.original_filename)
    pr_dir = uploads_dir_for(@pull_request)
    FileUtils.mkdir_p(pr_dir)
    dest = File.join(pr_dir, filename)
    FileUtils.cp(file.tempfile.path, dest)

    url = preflight_upload_path(pull_request_id: @pull_request.id, filename:)
    markdown = "![#{filename}](#{url})"

    render json: { url:, markdown:, filename: }, status: :created
  end

  def show
    pull_request_id = params[:pull_request_id]
    filename = params[:filename]
    file_path = File.join(uploads_base_dir, pull_request_id.to_s, filename)

    if File.exist?(file_path)
      send_file file_path, disposition: :inline
    else
      head :not_found
    end
  end

  private

  def uploads_base_dir
    ENV.fetch("PREFLIGHT_UPLOADS_PATH") { File.expand_path("~/.preflight/uploads") }
  end

  def uploads_dir_for(pull_request)
    File.join(uploads_base_dir, pull_request.id.to_s)
  end

  def sanitize_filename(filename)
    filename.gsub(/[^\w.\-]/, "_")
  end
end
```

- [ ] **Step 5: Run tests to verify they pass**

```bash
devbox run -- bin/rails test test/controllers/uploads_controller_test.rb
```

- [ ] **Step 6: Commit**

```bash
git add app/controllers/uploads_controller.rb test/controllers/uploads_controller_test.rb test/fixtures/files/
git commit -m "add image upload and serving controller"
```

### Task 12: Add image upload UI with Stimulus controller

**Files:**
- Create: `app/javascript/controllers/image_upload_controller.js`
- Modify: `app/views/pull_requests/show.html.erb`

- [ ] **Step 1: Install Stimulus (not yet set up in this project)**

```bash
devbox run -- bin/rails importmap:install
devbox run -- bin/rails stimulus:install
```

This will:
- Create `config/importmap.rb` and pin Stimulus
- Create `app/javascript/controllers/` with `application.js` and `index.js`
- Add `<%= javascript_importmap_tags %>` to the layout

After installation, verify the layout (`app/views/layouts/application.html.erb`) includes `javascript_importmap_tags` in the `<head>`. If it wasn't added automatically, add it manually.

**Important:** The existing show page uses vanilla JS `data-action` attributes (like `data-action="edit-description"` and `data-action="cancel-description"`) with inline `<script>` tags. Stimulus intercepts `data-action` attributes. The existing inline JS should be migrated to a Stimulus controller (e.g., `description_toggle_controller.js`) as part of this task, or the existing `data-action` attributes should be renamed to `data-role` to avoid conflicts. The simpler approach: rename the existing vanilla JS attributes from `data-action` to `data-role` and update the inline `<script>` selectors to match.

- [ ] **Step 2: Create the Stimulus controller**

Create `app/javascript/controllers/image_upload_controller.js`:

```javascript
import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["textarea", "dropzone", "fileInput"]

  connect() {
    this.textareaTarget.addEventListener("paste", this.handlePaste.bind(this))
  }

  dragover(event) {
    event.preventDefault()
    this.dropzoneTarget.classList.add("pf-dropzone--active")
  }

  dragleave(event) {
    event.preventDefault()
    this.dropzoneTarget.classList.remove("pf-dropzone--active")
  }

  drop(event) {
    event.preventDefault()
    this.dropzoneTarget.classList.remove("pf-dropzone--active")
    const files = event.dataTransfer.files
    if (files.length > 0) this.uploadFile(files[0])
  }

  selectFile() {
    this.fileInputTarget.click()
  }

  fileSelected(event) {
    const file = event.target.files[0]
    if (file) this.uploadFile(file)
  }

  handlePaste(event) {
    const items = event.clipboardData?.items
    if (!items) return

    for (const item of items) {
      if (item.type.startsWith("image/")) {
        event.preventDefault()
        this.uploadFile(item.getAsFile())
        return
      }
    }
  }

  async uploadFile(file) {
    const formData = new FormData()
    formData.append("file", file)

    const uploadUrl = this.element.dataset.imageUploadUrl

    try {
      const response = await fetch(uploadUrl, {
        method: "POST",
        body: formData,
        headers: { "X-CSRF-Token": document.querySelector("[name='csrf-token']")?.content }
      })

      if (response.ok) {
        const data = await response.json()
        this.insertAtCursor(data.markdown)
      } else {
        const error = await response.json()
        alert(error.error || "Upload failed")
      }
    } catch {
      alert("Upload failed — server may not be running")
    }
  }

  insertAtCursor(text) {
    const textarea = this.textareaTarget
    const start = textarea.selectionStart
    const end = textarea.selectionEnd
    const before = textarea.value.substring(0, start)
    const after = textarea.value.substring(end)
    const needsNewline = before.length > 0 && !before.endsWith("\n") ? "\n" : ""

    textarea.value = before + needsNewline + text + "\n" + after
    textarea.selectionStart = textarea.selectionEnd = start + needsNewline.length + text.length + 1
    textarea.focus()
  }
}
```

- [ ] **Step 3: Update the description edit form in show.html.erb**

In `app/views/pull_requests/show.html.erb`, replace the description form section (lines 30-39) with:

```erb
<div class="pf-card-body pf-description-edit" data-role="description-form" hidden>
  <%= form_with model: @pull_request, url: repository_pull_path(@local_repository, @pull_request), method: :patch do |form| %>
    <%= form.hidden_field :base_branch, value: @pull_request.base_branch %>
    <div data-controller="image-upload"
         data-image-upload-url="<%= repository_pull_uploads_path(@local_repository, @pull_request) %>">
      <%= form.text_area :description, rows: 16,
        class: "pf-description-edit__textarea",
        data: { image_upload_target: "textarea" } %>
      <div class="pf-dropzone"
           data-image-upload-target="dropzone"
           data-action="dragover->image-upload#dragover dragleave->image-upload#dragleave drop->image-upload#drop">
        <button type="button" class="pf-button pf-button--secondary pf-button--small"
                data-action="image-upload#selectFile">Attach an image</button>
        <span class="pf-dropzone__hint">or drag and drop, or paste</span>
        <input type="file" accept="image/png,image/jpeg,image/gif,image/webp" hidden
               data-image-upload-target="fileInput"
               data-action="image-upload#fileSelected">
      </div>
    </div>
    <div class="pf-description-edit__actions">
      <button type="button" class="pf-button pf-button--secondary pf-button--small" data-action="cancel-description">Cancel</button>
      <%= form.submit "Update comment", class: "pf-button pf-button--small" %>
    </div>
  <% end %>
</div>
```

- [ ] **Step 4: Verify the app boots and the page renders**

```bash
devbox run -- bin/rails runner "puts 'OK'"
```

- [ ] **Step 5: Commit**

```bash
git add app/javascript/controllers/image_upload_controller.js app/views/pull_requests/show.html.erb
git commit -m "add image upload with drag-and-drop, paste, and file picker"
```

### Task 13: Clean up images when PR is closed

**Files:**
- Modify: `app/models/pull_request.rb`

- [ ] **Step 1: Add after-save callback for cleanup**

In `app/models/pull_request.rb`, add:

```ruby
after_update :cleanup_uploads, if: :saved_change_to_status?
```

Add the private method:

```ruby
def cleanup_uploads
  return unless status == "closed"

  uploads_dir = File.join(
    ENV.fetch("PREFLIGHT_UPLOADS_PATH") { File.expand_path("~/.preflight/uploads") },
    id.to_s
  )
  FileUtils.rm_rf(uploads_dir) if Dir.exist?(uploads_dir)
end
```

- [ ] **Step 2: Write a test for cleanup**

Add to `test/models/pull_request_test.rb`:

```ruby
test "cleans up uploads directory when PR is closed" do
  with_sample_repository do |fixture|
    Dir.mktmpdir("preflight-uploads") do |uploads_dir|
      ENV["PREFLIGHT_UPLOADS_PATH"] = uploads_dir

      local_repository = create_local_repository!(fixture)
      pr = PullRequest.create!(local_repository:, source_branch: "feature", base_branch: "main")

      pr_uploads = File.join(uploads_dir, pr.id.to_s)
      FileUtils.mkdir_p(pr_uploads)
      File.write(File.join(pr_uploads, "test.png"), "fake")

      assert Dir.exist?(pr_uploads)

      pr.update!(status: "closed")

      assert_not Dir.exist?(pr_uploads)
    ensure
      ENV.delete("PREFLIGHT_UPLOADS_PATH")
    end
  end
end
```

- [ ] **Step 3: Run tests**

```bash
devbox run -- bin/rails test test/models/pull_request_test.rb
```

- [ ] **Step 4: Commit**

```bash
git add app/models/pull_request.rb test/models/pull_request_test.rb
git commit -m "clean up uploaded images when PR is closed"
```

---

## Chunk 4: GitHub Export

### Task 14: Create GithubCli service

**Files:**
- Create: `app/services/github_cli.rb`
- Create: `test/services/github_cli_test.rb`

- [ ] **Step 1: Write failing tests**

Create `test/services/github_cli_test.rb`:

```ruby
require "test_helper"

class GithubCliTest < ActiveSupport::TestCase
  test "available? returns false when gh is not installed" do
    GithubCli.stub(:which_gh, nil) do
      assert_not GithubCli.available?
    end
  end

  test "remote_branch_exists? checks remote refs" do
    with_sample_repository do |fixture|
      cli = GithubCli.new(repo_path: fixture.path)
      # No remote in test repo, so this should return false
      assert_not cli.remote_branch_exists?("main")
    end
  end
end
```

- [ ] **Step 2: Run tests to verify they fail**

```bash
devbox run -- bin/rails test test/services/github_cli_test.rb
```

- [ ] **Step 3: Create the service**

Create `app/services/github_cli.rb`:

```ruby
require "open3"

class GithubCli
  class Error < StandardError; end

  def self.available?
    which_gh.present?
  end

  def self.which_gh
    stdout, _, status = Open3.capture3("which", "gh")
    status.success? ? stdout.strip : nil
  rescue Errno::ENOENT
    nil
  end

  def initialize(repo_path:)
    @repo_path = repo_path
  end

  def create_pull_request(title:, body:, base:, head:, draft: true)
    args = ["pr", "create", "--title", title, "--body", body, "--base", base, "--head", head]
    args << "--draft" if draft

    stdout = gh(*args)
    stdout.strip
  end

  def pull_request_for_branch(branch)
    stdout = gh("pr", "list", "--head", branch, "--json", "url", "--limit", "1", allow_failure: true)
    return nil if stdout.blank?

    prs = JSON.parse(stdout)
    prs.first&.dig("url")
  rescue JSON::ParserError
    nil
  end

  def remote_branch_exists?(branch)
    stdout, _, status = Open3.capture3("git", "ls-remote", "--heads", "origin", branch, chdir: @repo_path)
    status.success? && stdout.strip.present?
  rescue Errno::ENOENT
    false
  end

  def has_remote?
    stdout, _, status = Open3.capture3("git", "remote", "get-url", "origin", chdir: @repo_path)
    status.success? && stdout.strip.present?
  rescue Errno::ENOENT
    false
  end

  private

  def gh(*args, allow_failure: false)
    stdout, stderr, status = Open3.capture3("gh", *args, chdir: @repo_path)
    return stdout.strip if status.success?
    return "" if allow_failure

    raise Error, "gh #{args.join(' ')} failed: #{stderr}"
  end
end
```

- [ ] **Step 4: Run tests**

```bash
devbox run -- bin/rails test test/services/github_cli_test.rb
```

- [ ] **Step 5: Commit**

```bash
git add app/services/github_cli.rb test/services/github_cli_test.rb
git commit -m "add GithubCli service wrapping gh CLI interactions"
```

### Task 15: Create GithubExportsController

**Files:**
- Create: `app/controllers/github_exports_controller.rb`
- Create: `test/controllers/github_exports_controller_test.rb`
- Modify: `config/routes.rb`

- [ ] **Step 1: Write failing tests**

(The route was already added in Task 10.)

Create `test/controllers/github_exports_controller_test.rb`:

```ruby
require "test_helper"

class GithubExportsControllerTest < ActionDispatch::IntegrationTest
  test "POST github_export redirects with alert when gh is not available" do
    with_sample_repository do |fixture|
      local_repository = create_local_repository!(fixture)
      pull_request = PullRequest.create!(
        local_repository:, source_branch: "feature", base_branch: "main"
      )

      GithubCli.stub(:available?, false) do
        post repository_pull_github_export_path(local_repository, pull_request)
      end

      assert_redirected_to repository_pull_path(local_repository, pull_request)
      assert_match "not installed", flash[:alert]
    end
  end
end
```

- [ ] **Step 2: Run test to verify it fails**

```bash
devbox run -- bin/rails test test/controllers/github_exports_controller_test.rb
```

- [ ] **Step 3: Create the controller**

Create `app/controllers/github_exports_controller.rb`:

```ruby
class GithubExportsController < ApplicationController
  include RepositoryScoped

  def create
    @pull_request = @local_repository.pull_requests.find(params[:id])
    github_cli = GithubCli.new(repo_path: @local_repository.path)

    unless GithubCli.available?
      return redirect_to repository_pull_path(@local_repository, @pull_request),
        alert: "GitHub CLI (gh) is not installed. Install it to export PRs to GitHub."
    end

    unless github_cli.has_remote?
      return redirect_to repository_pull_path(@local_repository, @pull_request),
        alert: "This repository has no remote. Push to GitHub first."
    end

    existing_url = github_cli.pull_request_for_branch(@pull_request.source_branch)
    if existing_url
      @pull_request.update!(status: "closed", github_pr_url: existing_url)
      return redirect_to repository_pull_path(@local_repository, @pull_request),
        notice: "A GitHub PR already exists for this branch."
    end

    base = resolve_base_branch(github_cli)
    body = strip_local_image_warning(@pull_request.description)

    begin
      pr_url = github_cli.create_pull_request(
        title: @pull_request.title,
        body:,
        base:,
        head: @pull_request.source_branch,
        draft: true
      )

      @pull_request.update!(status: "closed", github_pr_url: pr_url)

      redirect_to repository_pull_path(@local_repository, @pull_request),
        notice: "GitHub PR created: #{pr_url}"
    rescue GithubCli::Error => e
      redirect_to repository_pull_path(@local_repository, @pull_request),
        alert: "Failed to create GitHub PR: #{e.message}"
    end
  end

  private

  def resolve_base_branch(github_cli)
    if github_cli.remote_branch_exists?(@pull_request.base_branch)
      @pull_request.base_branch
    else
      @local_repository.default_branch
    end
  end

  def strip_local_image_warning(description)
    has_local_images = description.include?("/_preflight/uploads/")
    if has_local_images
      warning = "\n\n---\n_Note: This PR was drafted in Preflight. Some images were local-only and are not included._\n"
      description + warning
    else
      description
    end
  end
end
```

- [ ] **Step 4: Run tests**

```bash
devbox run -- bin/rails test test/controllers/github_exports_controller_test.rb
```

- [ ] **Step 5: Commit**

```bash
git add app/controllers/github_exports_controller.rb test/controllers/github_exports_controller_test.rb
git commit -m "add GitHub export controller with gh CLI integration"
```

### Task 16: Add GitHub export button and closed state to PR show page

**Files:**
- Modify: `app/views/pull_requests/show.html.erb`
- Modify: `app/controllers/pull_requests_controller.rb`

- [ ] **Step 1: Add helper data to the controller**

In `app/controllers/pull_requests_controller.rb`, update `load_pull_request_data`:

```ruby
def load_pull_request_data
  @comparison = @pull_request.comparison
  @branches = @local_repository.branches
  @gh_available = GithubCli.available?
  @can_export = @gh_available && GithubCli.new(repo_path: @local_repository.path).has_remote? && @pull_request.status == "open"
end
```

- [ ] **Step 2: Update show.html.erb with export button and closed state**

In `app/views/pull_requests/show.html.erb`, replace the merge box section (lines 67-75) with:

```erb
<% if @pull_request.status == "closed" && @pull_request.github_pr_url.present? %>
  <li class="pf-timeline-item pf-timeline-item--merge">
    <div class="pf-timeline-badge pf-timeline-badge--merge" aria-hidden="true">&#10003;</div>
    <section class="pf-merge-box pf-merge-box--closed">
      <header class="pf-merge-box__header">
        <strong>Exported to GitHub</strong>
      </header>
      <p class="pf-merge-box__body">
        This preflight PR has been exported.
        <%= link_to "View on GitHub →", @pull_request.github_pr_url, target: "_blank", rel: "noopener" %>
      </p>
    </section>
  </li>
<% elsif @can_export %>
  <li class="pf-timeline-item pf-timeline-item--merge">
    <div class="pf-timeline-badge pf-timeline-badge--merge" aria-hidden="true">&#10003;</div>
    <section class="pf-merge-box">
      <header class="pf-merge-box__header">
        <strong>Ready to export</strong>
      </header>
      <p class="pf-merge-box__body">Review the files changed and update the description, then create a draft PR on GitHub.</p>
      <%= button_to "Create PR on GitHub",
        repository_pull_github_export_path(@local_repository, @pull_request),
        method: :post,
        class: "pf-button" %>
    </section>
  </li>
<% else %>
  <li class="pf-timeline-item pf-timeline-item--merge">
    <div class="pf-timeline-badge pf-timeline-badge--merge" aria-hidden="true">&#10003;</div>
    <section class="pf-merge-box">
      <header class="pf-merge-box__header">
        <strong>No conflicts with base branch</strong>
      </header>
      <p class="pf-merge-box__body">
        <% unless @gh_available %>
          Install the <a href="https://cli.github.com" target="_blank" rel="noopener">GitHub CLI</a> to export PRs to GitHub.
        <% else %>
          Review the files changed and update the description before you push this branch upstream.
        <% end %>
      </p>
    </section>
  </li>
<% end %>
```

- [ ] **Step 3: Disable edit button when PR is closed**

Update the edit button (line 23) to be conditional:

```erb
<% if @pull_request.status == "open" %>
  <button type="button" class="pf-button pf-button--secondary pf-button--small" data-action="edit-description">Edit</button>
<% end %>
```

- [ ] **Step 4: Verify page renders**

```bash
devbox run -- bin/rails runner "puts 'OK'"
```

- [ ] **Step 5: Commit**

```bash
git add app/views/pull_requests/show.html.erb app/controllers/pull_requests_controller.rb
git commit -m "add GitHub export button and closed state to PR show page"
```

### Task 17: Add open/closed filter to PR index

**Files:**
- Modify: `app/views/pull_requests/index.html.erb`
- Modify: `app/controllers/pull_requests_controller.rb`

- [ ] **Step 1: Update controller index action**

```ruby
def index
  @current_filter = params[:status] == "closed" ? :closed : :open
  @pull_requests = @local_repository.pull_requests.where(status: @current_filter).order(created_at: :desc)
end
```

- [ ] **Step 2: Add filter tabs to index view**

In `app/views/pull_requests/index.html.erb`, after the pulls header div (line 7), add:

```erb
<div class="pf-pulls-filters">
  <%= link_to repository_pulls_path(@local_repository, status: "open"),
    class: "pf-pulls-filter #{"pf-pulls-filter--active" if @current_filter == :open}" do %>
    <%= octicon(:git_pull_request, size: 16) %> Open
  <% end %>
  <%= link_to repository_pulls_path(@local_repository, status: "closed"),
    class: "pf-pulls-filter #{"pf-pulls-filter--active" if @current_filter == :closed}" do %>
    <%= octicon(:check, size: 16) %> Closed
  <% end %>
</div>
```

- [ ] **Step 3: Run full test suite**

```bash
devbox run -- bin/rails test
```

- [ ] **Step 4: Commit**

```bash
git add app/views/pull_requests/index.html.erb app/controllers/pull_requests_controller.rb
git commit -m "add open/closed filter tabs to PR index"
```

---

## Chunk 5: Go CLI

### Task 18: Initialize Go module

**Files:**
- Create: `cli/go.mod`
- Create: `cli/main.go`
- Create: `cli/cmd/root.go`

- [ ] **Step 1: Create CLI directory and initialize Go module**

```bash
mkdir -p cli/cmd cli/internal/server cli/internal/git cli/internal/db cli/internal/config
cd cli && go mod init github.com/zhubert/preflight-cli && cd ..
```

- [ ] **Step 2: Install dependencies**

```bash
cd cli && go get github.com/spf13/cobra@latest && go get modernc.org/sqlite@latest && cd ..
```

- [ ] **Step 3: Create main.go**

Create `cli/main.go`:

```go
package main

import "github.com/zhubert/preflight-cli/cmd"

func main() {
	cmd.Execute()
}
```

- [ ] **Step 4: Create root command**

Create `cli/cmd/root.go`:

```go
package cmd

import (
	"fmt"
	"os"

	"github.com/spf13/cobra"
)

var rootCmd = &cobra.Command{
	Use:   "preflight",
	Short: "Local PR review before pushing to GitHub",
}

func Execute() {
	if err := rootCmd.Execute(); err != nil {
		fmt.Fprintln(os.Stderr, err)
		os.Exit(1)
	}
}
```

- [ ] **Step 5: Verify it compiles**

```bash
cd cli && go build -o ../tmp/preflight . && cd ..
./tmp/preflight --help
```

Expected: shows help text with "Local PR review before pushing to GitHub"

- [ ] **Step 6: Commit**

```bash
git add cli/
git commit -m "initialize Go CLI module with cobra"
```

### Task 19: Config paths and server manager

**Files:**
- Create: `cli/internal/config/paths.go`
- Create: `cli/internal/server/manager.go`

- [ ] **Step 1: Create path constants**

Create `cli/internal/config/paths.go`:

```go
package config

import (
	"os"
	"path/filepath"
)

func HomeDir() string {
	home, _ := os.UserHomeDir()
	return filepath.Join(home, ".preflight")
}

func DBPath() string {
	return filepath.Join(HomeDir(), "db.sqlite3")
}

func PIDPath() string {
	return filepath.Join(HomeDir(), "preflight.pid")
}

func LogPath() string {
	return filepath.Join(HomeDir(), "preflight.log")
}

func EnsureHomeDir() error {
	return os.MkdirAll(HomeDir(), 0755)
}
```

- [ ] **Step 2: Create server manager and API client**

Create `cli/internal/server/manager.go` (process lifecycle only):

```go
package server

import (
	"encoding/json"
	"fmt"
	"net/http"
	"os"
	"os/exec"
	"path/filepath"
	"strconv"
	"strings"
	"syscall"
	"time"

	"github.com/zhubert/preflight-cli/internal/config"
)

const (
	DefaultPort    = 3000
	HealthEndpoint = "/api/status"
	StartTimeout   = 15 * time.Second
)

func ServerURL() string {
	return fmt.Sprintf("http://localhost:%d", DefaultPort)
}

func IsRunning() bool {
	pid, err := readPID()
	if err != nil {
		return false
	}
	process, err := os.FindProcess(pid)
	if err != nil {
		return false
	}
	return process.Signal(syscall.Signal(0)) == nil
}

func EnsureRunning() error {
	if IsRunning() {
		return nil
	}
	return Start()
}

func Start() error {
	if IsRunning() {
		return fmt.Errorf("server is already running")
	}

	if err := config.EnsureHomeDir(); err != nil {
		return fmt.Errorf("failed to create ~/.preflight: %w", err)
	}

	serverBin, serverArgs := findServerCommand()
	if serverBin == "" {
		return fmt.Errorf("could not find preflight server. Is it installed correctly?")
	}

	logFile, err := os.OpenFile(config.LogPath(), os.O_APPEND|os.O_CREATE|os.O_WRONLY, 0644)
	if err != nil {
		return fmt.Errorf("failed to open log file: %w", err)
	}

	cmd := exec.Command(serverBin, serverArgs...)
	cmd.Stdout = logFile
	cmd.Stderr = logFile
	cmd.Env = append(os.Environ(),
		fmt.Sprintf("PREFLIGHT_DB_PATH=%s", config.DBPath()),
		fmt.Sprintf("PIDFILE=%s", config.PIDPath()),
		fmt.Sprintf("PORT=%d", DefaultPort),
		"PREFLIGHT_IDLE_SHUTDOWN=1",
		fmt.Sprintf("PREFLIGHT_UPLOADS_PATH=%s", filepath.Join(config.HomeDir(), "uploads")),
		"RAILS_ENV=production",
	)

	if err := cmd.Start(); err != nil {
		logFile.Close()
		return fmt.Errorf("failed to start server: %w", err)
	}

	// Detach so server survives CLI exit
	cmd.Process.Release()
	logFile.Close()

	// Don't write PID here — let Puma write it via PIDFILE env var
	// to avoid a race condition where we write the wrong PID

	// Wait for Puma to write PID file and become healthy
	return waitForHealthy(StartTimeout)
}

func Stop() error {
	pid, err := readPID()
	if err != nil {
		return fmt.Errorf("server is not running (no PID file)")
	}

	process, err := os.FindProcess(pid)
	if err != nil {
		return fmt.Errorf("could not find process %d: %w", pid, err)
	}

	if err := process.Signal(syscall.SIGTERM); err != nil {
		return fmt.Errorf("could not stop server: %w", err)
	}

	// Wait for process to exit
	for i := 0; i < 30; i++ {
		if process.Signal(syscall.Signal(0)) != nil {
			break
		}
		time.Sleep(100 * time.Millisecond)
	}

	os.Remove(config.PIDPath())
	return nil
}

func Restart() error {
	if IsRunning() {
		if err := Stop(); err != nil {
			return err
		}
	}
	return Start()
}

func waitForHealthy(timeout time.Duration) error {
	deadline := time.Now().Add(timeout)
	url := fmt.Sprintf("%s%s", ServerURL(), HealthEndpoint)

	for time.Now().Before(deadline) {
		resp, err := http.Get(url)
		if err == nil {
			resp.Body.Close()
			if resp.StatusCode == 200 {
				return nil
			}
		}
		time.Sleep(500 * time.Millisecond)
	}

	return fmt.Errorf("server did not become healthy within %s", timeout)
}

func readPID() (int, error) {
	data, err := os.ReadFile(config.PIDPath())
	if err != nil {
		return 0, err
	}
	return strconv.Atoi(strings.TrimSpace(string(data)))
}

func findServerCommand() (string, []string) {
	// Look for the server start script relative to the CLI binary (production)
	exe, err := os.Executable()
	if err != nil {
		return "", nil
	}
	dir := filepath.Dir(filepath.Dir(exe)) // go from bin/ to prefix/
	candidate := filepath.Join(dir, "libexec", "bin", "start-server")
	if _, err := os.Stat(candidate); err == nil {
		return candidate, nil
	}

	// Fallback: development mode — look for bin/rails in parent directory
	devCandidate := filepath.Join(filepath.Dir(filepath.Dir(exe)), "bin", "rails")
	if _, err := os.Stat(devCandidate); err == nil {
		return devCandidate, []string{"server"}
	}

	return "", nil
}
```

Create `cli/internal/server/api.go` (HTTP API client):

```go
package server

import (
	"encoding/json"
	"fmt"
	"net/http"
	"strings"
)

func CreatePullRequest(repoPath, sourceBranch, baseBranch string) (map[string]interface{}, error) {
	url := fmt.Sprintf("%s/api/pull_requests", ServerURL())

	payload := map[string]string{
		"repo_path":     repoPath,
		"source_branch": sourceBranch,
		"base_branch":   baseBranch,
	}
	body, _ := json.Marshal(payload)

	resp, err := http.Post(url, "application/json", strings.NewReader(string(body)))
	if err != nil {
		return nil, fmt.Errorf("failed to contact server: %w", err)
	}
	defer resp.Body.Close()

	var result map[string]interface{}
	if err := json.NewDecoder(resp.Body).Decode(&result); err != nil {
		return nil, fmt.Errorf("invalid response from server: %w", err)
	}

	if resp.StatusCode >= 400 {
		errors, _ := result["errors"]
		return nil, fmt.Errorf("server error: %v", errors)
	}

	return result, nil
}

func FindPullRequest(repoPath, sourceBranch string) (map[string]interface{}, error) {
	url := fmt.Sprintf("%s/api/pull_requests?repo_path=%s&source_branch=%s",
		ServerURL(), repoPath, sourceBranch)

	resp, err := http.Get(url)
	if err != nil {
		return nil, fmt.Errorf("failed to contact server: %w", err)
	}
	defer resp.Body.Close()

	if resp.StatusCode == 404 {
		return nil, nil
	}

	var result map[string]interface{}
	if err := json.NewDecoder(resp.Body).Decode(&result); err != nil {
		return nil, fmt.Errorf("invalid response from server: %w", err)
	}

	return result, nil
}
```

- [ ] **Step 3: Verify it compiles**

```bash
cd cli && go build ./... && cd ..
```

- [ ] **Step 4: Commit**

```bash
git add cli/internal/
git commit -m "add config paths, server process manager, and API client"
```

### Task 20: Git helper for CLI

**Files:**
- Create: `cli/internal/git/repo.go`

- [ ] **Step 1: Create git helper**

Create `cli/internal/git/repo.go`:

```go
package git

import (
	"fmt"
	"os/exec"
	"path/filepath"
	"strings"
)

func RepoRoot() (string, error) {
	out, err := run("rev-parse", "--show-toplevel")
	if err != nil {
		return "", fmt.Errorf("not a git repository")
	}
	return filepath.Clean(out), nil
}

func CurrentBranch() (string, error) {
	out, err := run("branch", "--show-current")
	if err != nil {
		return "", fmt.Errorf("failed to get current branch: %w", err)
	}
	if out == "" {
		return "", fmt.Errorf("HEAD is detached — checkout a branch first")
	}
	return out, nil
}

func DefaultBranch() (string, error) {
	// Try origin/HEAD first
	out, err := run("symbolic-ref", "--quiet", "--short", "refs/remotes/origin/HEAD")
	if err == nil && out != "" {
		parts := strings.Split(out, "/")
		return parts[len(parts)-1], nil
	}

	// Fall back to checking if main exists
	if _, err := run("rev-parse", "--verify", "--quiet", "refs/heads/main"); err == nil {
		return "main", nil
	}

	// Fall back to master
	if _, err := run("rev-parse", "--verify", "--quiet", "refs/heads/master"); err == nil {
		return "master", nil
	}

	return CurrentBranch()
}

func run(args ...string) (string, error) {
	cmd := exec.Command("git", args...)
	out, err := cmd.Output()
	if err != nil {
		return "", err
	}
	return strings.TrimSpace(string(out)), nil
}
```

- [ ] **Step 2: Verify it compiles**

```bash
cd cli && go build ./... && cd ..
```

- [ ] **Step 3: Commit**

```bash
git add cli/internal/git/
git commit -m "add git helper for CLI (repo root, current branch, default branch)"
```

### Task 21: SQLite reader for list command

**Files:**
- Create: `cli/internal/db/queries.go`

- [ ] **Step 1: Create SQLite query helper**

Create `cli/internal/db/queries.go`:

```go
package db

import (
	"database/sql"
	"fmt"
	"time"

	"github.com/zhubert/preflight-cli/internal/config"
	_ "modernc.org/sqlite"
)

type PullRequestRow struct {
	RepoName     string
	SourceBranch string
	CreatedAt    time.Time
}

func ListOpenPullRequests() ([]PullRequestRow, error) {
	dbPath := config.DBPath()
	db, err := sql.Open("sqlite", dbPath)
	if err != nil {
		return nil, fmt.Errorf("failed to open database at %s: %w", dbPath, err)
	}
	defer db.Close()

	rows, err := db.Query(`
		SELECT lr.name, pr.source_branch, pr.created_at
		FROM pull_requests pr
		JOIN local_repositories lr ON lr.id = pr.local_repository_id
		WHERE pr.status = 'open'
		ORDER BY pr.created_at DESC
	`)
	if err != nil {
		return nil, fmt.Errorf("query failed: %w", err)
	}
	defer rows.Close()

	var results []PullRequestRow
	for rows.Next() {
		var r PullRequestRow
		var createdStr string
		if err := rows.Scan(&r.RepoName, &r.SourceBranch, &createdStr); err != nil {
			return nil, fmt.Errorf("scan failed: %w", err)
		}
		// Rails/SQLite may store as "2006-01-02 15:04:05.999999" or "2006-01-02T15:04:05.999999"
		for _, layout := range []string{
			"2006-01-02 15:04:05.999999",
			"2006-01-02T15:04:05.999999",
			"2006-01-02 15:04:05",
			time.RFC3339,
		} {
			if t, err := time.Parse(layout, createdStr); err == nil {
				r.CreatedAt = t
				break
			}
		}
		results = append(results, r)
	}
	return results, nil
}
```

- [ ] **Step 2: Verify it compiles**

```bash
cd cli && go build ./... && cd ..
```

- [ ] **Step 3: Commit**

```bash
git add cli/internal/db/
git commit -m "add SQLite reader for listing open PRs"
```

### Task 22: Implement CLI commands

**Files:**
- Create: `cli/cmd/push.go`
- Create: `cli/cmd/open.go`
- Create: `cli/cmd/list.go`
- Create: `cli/cmd/server.go`

- [ ] **Step 1: Create push command**

Create `cli/cmd/push.go`:

```go
package cmd

import (
	"fmt"
	"os"
	"os/exec"
	"runtime"

	"github.com/spf13/cobra"
	"github.com/zhubert/preflight-cli/internal/git"
	"github.com/zhubert/preflight-cli/internal/server"
)

var baseBranch string

var pushCmd = &cobra.Command{
	Use:   "push",
	Short: "Create or open a preflight PR for the current branch",
	RunE: func(cmd *cobra.Command, args []string) error {
		repoPath, err := git.RepoRoot()
		if err != nil {
			return err
		}

		branch, err := git.CurrentBranch()
		if err != nil {
			return err
		}

		base := baseBranch
		if base == "" {
			base, err = git.DefaultBranch()
			if err != nil {
				return fmt.Errorf("could not determine default branch: %w", err)
			}
		}

		if branch == base {
			return fmt.Errorf("you're on %s — switch to a feature branch first", base)
		}

		fmt.Println("Starting preflight server...")
		if err := server.EnsureRunning(); err != nil {
			return fmt.Errorf("failed to start server: %w", err)
		}

		fmt.Printf("Creating PR for %s → %s...\n", branch, base)
		result, err := server.CreatePullRequest(repoPath, branch, base)
		if err != nil {
			return err
		}

		path, _ := result["url"].(string)
		repoName, _ := result["repository_name"].(string)
		created, _ := result["created"].(bool)
		fullURL := fmt.Sprintf("%s%s", server.ServerURL(), path)

		if created {
			fmt.Printf("Created preflight PR in %s\n", repoName)
		} else {
			fmt.Printf("Opened existing preflight PR in %s\n", repoName)
		}

		fmt.Printf("Opening %s\n", fullURL)
		return openBrowser(fullURL)
	},
}

func init() {
	pushCmd.Flags().StringVar(&baseBranch, "base", "", "Base branch (defaults to main/master)")
	rootCmd.AddCommand(pushCmd)
}

func openBrowser(url string) error {
	var cmd *exec.Cmd
	switch runtime.GOOS {
	case "darwin":
		cmd = exec.Command("open", url)
	case "linux":
		cmd = exec.Command("xdg-open", url)
	default:
		fmt.Fprintf(os.Stderr, "Open this URL in your browser: %s\n", url)
		return nil
	}
	return cmd.Start()
}
```

- [ ] **Step 2: Create open command**

Create `cli/cmd/open.go`:

```go
package cmd

import (
	"fmt"

	"github.com/spf13/cobra"
	"github.com/zhubert/preflight-cli/internal/git"
	"github.com/zhubert/preflight-cli/internal/server"
)

var openCmd = &cobra.Command{
	Use:   "open",
	Short: "Open the preflight PR for the current branch in your browser",
	RunE: func(cmd *cobra.Command, args []string) error {
		repoPath, err := git.RepoRoot()
		if err != nil {
			return err
		}

		branch, err := git.CurrentBranch()
		if err != nil {
			return err
		}

		if err := server.EnsureRunning(); err != nil {
			return fmt.Errorf("failed to start server: %w", err)
		}

		result, err := server.FindPullRequest(repoPath, branch)
		if err != nil {
			return fmt.Errorf("failed to look up PR: %w", err)
		}
		if result == nil {
			return fmt.Errorf("no preflight PR found for branch %s — use 'preflight push' to create one", branch)
		}

		url, _ := result["url"].(string)
		fullURL := fmt.Sprintf("%s%s", server.ServerURL(), url)
		fmt.Printf("Opening %s\n", fullURL)
		return openBrowser(fullURL)
	},
}

func init() {
	rootCmd.AddCommand(openCmd)
}
```

- [ ] **Step 3: Create list command**

Create `cli/cmd/list.go`:

```go
package cmd

import (
	"fmt"
	"os"
	"text/tabwriter"
	"time"

	"github.com/spf13/cobra"
	"github.com/zhubert/preflight-cli/internal/db"
)

var listCmd = &cobra.Command{
	Use:   "list",
	Short: "List all open preflight PRs",
	RunE: func(cmd *cobra.Command, args []string) error {
		prs, err := db.ListOpenPullRequests()
		if err != nil {
			return fmt.Errorf("failed to list PRs: %w", err)
		}

		if len(prs) == 0 {
			fmt.Println("No open preflight PRs.")
			return nil
		}

		w := tabwriter.NewWriter(os.Stdout, 0, 0, 2, ' ', 0)
		fmt.Fprintln(w, "REPO\tBRANCH\tCREATED")
		for _, pr := range prs {
			fmt.Fprintf(w, "%s\t%s\t%s\n", pr.RepoName, pr.SourceBranch, timeAgo(pr.CreatedAt))
		}
		w.Flush()
		return nil
	},
}

func init() {
	rootCmd.AddCommand(listCmd)
}

func timeAgo(t time.Time) string {
	d := time.Since(t)
	switch {
	case d < time.Minute:
		return "just now"
	case d < time.Hour:
		m := int(d.Minutes())
		if m == 1 {
			return "1 minute ago"
		}
		return fmt.Sprintf("%d minutes ago", m)
	case d < 24*time.Hour:
		h := int(d.Hours())
		if h == 1 {
			return "1 hour ago"
		}
		return fmt.Sprintf("%d hours ago", h)
	default:
		days := int(d.Hours() / 24)
		if days == 1 {
			return "yesterday"
		}
		return fmt.Sprintf("%d days ago", days)
	}
}
```

- [ ] **Step 4: Create server command**

Create `cli/cmd/server.go`:

```go
package cmd

import (
	"fmt"

	"github.com/spf13/cobra"
	"github.com/zhubert/preflight-cli/internal/server"
)

var serverCmd = &cobra.Command{
	Use:   "server",
	Short: "Manage the preflight server",
}

var serverStartCmd = &cobra.Command{
	Use:   "start",
	Short: "Start the preflight server",
	RunE: func(cmd *cobra.Command, args []string) error {
		fmt.Println("Starting preflight server...")
		if err := server.Start(); err != nil {
			return err
		}
		fmt.Printf("Server running at %s\n", server.ServerURL())
		return nil
	},
}

var serverStopCmd = &cobra.Command{
	Use:   "stop",
	Short: "Stop the preflight server",
	RunE: func(cmd *cobra.Command, args []string) error {
		fmt.Println("Stopping preflight server...")
		if err := server.Stop(); err != nil {
			return err
		}
		fmt.Println("Server stopped.")
		return nil
	},
}

var serverRestartCmd = &cobra.Command{
	Use:   "restart",
	Short: "Restart the preflight server",
	RunE: func(cmd *cobra.Command, args []string) error {
		fmt.Println("Restarting preflight server...")
		if err := server.Restart(); err != nil {
			return err
		}
		fmt.Printf("Server running at %s\n", server.ServerURL())
		return nil
	},
}

func init() {
	serverCmd.AddCommand(serverStartCmd)
	serverCmd.AddCommand(serverStopCmd)
	serverCmd.AddCommand(serverRestartCmd)
	rootCmd.AddCommand(serverCmd)
}
```

- [ ] **Step 5: Build and test**

```bash
cd cli && go build -o ../tmp/preflight . && cd ..
./tmp/preflight --help
./tmp/preflight push --help
./tmp/preflight list
./tmp/preflight server --help
```

- [ ] **Step 6: Commit**

```bash
git add cli/cmd/
git commit -m "implement CLI commands: push, open, list, server"
```

---

## Chunk 6: Distribution Scaffolding

### Task 23: Create server start script

**Files:**
- Create: `script/start-server`

- [ ] **Step 1: Create the script**

Create `script/start-server`:

```bash
#!/usr/bin/env bash
set -e

# Resolve the directory where this script lives
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
LIBEXEC_DIR="$(dirname "$SCRIPT_DIR")"

# Use bundled Ruby if available, otherwise system Ruby
if [ -d "$LIBEXEC_DIR/ruby/bin" ]; then
  export PATH="$LIBEXEC_DIR/ruby/bin:$PATH"
  export GEM_HOME="$LIBEXEC_DIR/vendor/bundle"
  export GEM_PATH="$GEM_HOME"
fi

export BUNDLE_GEMFILE="$LIBEXEC_DIR/server/Gemfile"
export BUNDLE_PATH="$LIBEXEC_DIR/vendor/bundle"

cd "$LIBEXEC_DIR/server"
exec bundle exec rails server "$@"
```

- [ ] **Step 2: Make executable**

```bash
chmod +x script/start-server
```

- [ ] **Step 3: Commit**

```bash
git add script/start-server
git commit -m "add server start script for packaged distribution"
```

### Task 24: Create Homebrew formula skeleton

**Files:**
- Create: `Formula/preflight.rb` (in a separate homebrew-preflight repo, documented here)

- [ ] **Step 1: Document the formula structure**

This task creates the Homebrew formula. The formula will live in a separate `homebrew-preflight` tap repository. Here is the template:

```ruby
class Preflight < Formula
  desc "Local PR review before pushing to GitHub"
  homepage "https://github.com/zhubert/preflight"
  version "0.1.0"

  on_macos do
    if Hardware::CPU.arm?
      url "https://github.com/zhubert/preflight/releases/download/v#{version}/preflight-darwin-arm64.tar.gz"
      sha256 "PLACEHOLDER"
    else
      url "https://github.com/zhubert/preflight/releases/download/v#{version}/preflight-darwin-amd64.tar.gz"
      sha256 "PLACEHOLDER"
    end
  end

  on_linux do
    if Hardware::CPU.arm?
      url "https://github.com/zhubert/preflight/releases/download/v#{version}/preflight-linux-arm64.tar.gz"
      sha256 "PLACEHOLDER"
    else
      url "https://github.com/zhubert/preflight/releases/download/v#{version}/preflight-linux-amd64.tar.gz"
      sha256 "PLACEHOLDER"
    end
  end

  def install
    bin.install "preflight"
    libexec.install Dir["libexec/*"]
  end

  test do
    assert_match "Local PR review", shell_output("#{bin}/preflight --help")
  end
end
```

- [ ] **Step 2: Create .goreleaser.yml for CLI builds**

Create `.goreleaser.yml` at the repo root:

```yaml
version: 2

builds:
  - id: preflight
    dir: cli
    main: .
    binary: preflight
    env:
      - CGO_ENABLED=0
    goos:
      - darwin
      - linux
    goarch:
      - amd64
      - arm64

archives:
  - id: preflight
    builds: [preflight]
    format: tar.gz
    name_template: "preflight-{{ .Os }}-{{ .Arch }}"

release:
  github:
    owner: zhubert
    name: preflight
```

- [ ] **Step 3: Commit**

```bash
git add .goreleaser.yml
git commit -m "add goreleaser config for CLI binary distribution"
```

### Task 25: Create GitHub Actions release workflow

**Files:**
- Create: `.github/workflows/release.yml`

- [ ] **Step 1: Create the workflow**

Create `.github/workflows/release.yml`:

```yaml
name: Release

on:
  push:
    tags:
      - 'v*'

permissions:
  contents: write

jobs:
  release:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
        with:
          fetch-depth: 0

      - uses: actions/setup-go@v5
        with:
          go-version: '1.22'

      - name: Run GoReleaser
        uses: goreleaser/goreleaser-action@v6
        with:
          version: latest
          args: release --clean
        env:
          GITHUB_TOKEN: ${{ secrets.GITHUB_TOKEN }}
```

Note: The Ruby bundling step for the server package will be added during the bundled Ruby strategy evaluation. For now, this builds and releases the Go CLI binary only.

- [ ] **Step 2: Commit**

```bash
git add .github/workflows/release.yml
git commit -m "add GitHub Actions release workflow for CLI builds"
```

---

## Post-Implementation

After all chunks are complete:

1. **Manual testing**: Run `preflight push` from a real repository, create a PR, add images, export to GitHub
2. **Bundled Ruby evaluation**: Test Traveling Ruby and static Ruby builds for macOS arm64/amd64
3. **Homebrew tap setup**: Create the `homebrew-preflight` repository, publish first formula
4. **Add `.superpowers/` to `.gitignore`** if not already there
