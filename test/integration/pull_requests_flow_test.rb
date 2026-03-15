require "test_helper"

class PullRequestsFlowTest < ActionDispatch::IntegrationTest
  test "creates a local pull request from a branch comparison" do
    with_sample_repository do |fixture|
      repository = create_local_repository!(fixture)
      get repository_compare_path(repository)

      assert_response :success
      assert_select "form[action='#{repository_pulls_path(repository)}']"
      assert_select "select[name='source_branch'] option", text: "feature"
      assert_select "select[name='base_branch'] option[selected='selected']", text: "main"
      assert_select "input[name='pull_request[source_branch]'][value='feature']", count: 1
      assert_select "input[name='pull_request[base_branch]'][value='main']", count: 1

      post repository_pulls_path(repository), params: {
        pull_request: {
          source_branch: "feature",
          description: "Review the widget work."
        }
      }

      pull_request = PullRequest.order(:created_at).last

      assert_redirected_to repository_pull_path(repository, pull_request)
      follow_redirect!
      assert_response :success
      assert_select "h1", text: "feature"
      assert_select "summary[aria-label='Edit title']"
      assert_select "a[href='#{repository_pull_path(repository, pull_request)}']", text: /Conversation/
      assert_select "a[href='#{repository_pull_commits_path(repository, pull_request)}']", text: /Commits/
      assert_select "a[href='#{repository_pull_files_path(repository, pull_request)}']", text: /Files changed/
      assert_select "[data-role='conversation-card']", text: /Review the widget work\./
      assert_select "[data-role='conversation-commit-list'] a[href='#{repository_pull_commit_path(repository, pull_request, fixture.feature_commits[:add_widget])}']", text: /Add widget/
      assert_select "[data-role='conversation-commit-list'] a[href='#{repository_pull_commit_path(repository, pull_request, fixture.feature_commits[:refine_widget])}']", text: /Refine widget/
      assert_select ".pf-merge-box", text: /No conflicts with base branch/
      assert_select "[data-role='pr-sidebar']", count: 0
      assert_select "[data-role='branch-pill']", text: "main"
      assert_select "[data-role='branch-pill']", text: "feature"
      assert_select "[data-role='pr-summary']"

      get repository_pull_files_path(repository, pull_request)
      assert_select ".pf-page--wide"
      assert_select "input[name='q']"
      assert_select "[data-role='diff-settings']"
      assert_select "[data-role='split-diff']"
      assert_select "summary[aria-label='Edit title']", count: 0
      assert_select ".pf-repository-nav", count: 0
      assert_select ".pf-pr-actions", count: 0
      assert_select ".pf-code .k, .pf-code .nf, .pf-code .nb", minimum: 1
      assert_select "[data-role='file-tree']", text: /app/
      assert_select "[data-role='file-tree']", text: /models/
      assert_select "[data-role='file-tree']", text: /README\.md/
      assert_select "[data-role='file-tree']", text: /widget\.rb/
      assert_select "[data-role='file-tree'] a[href='#file-readme-md']"
      assert_select "[data-role='file-tree'] a[href='#file-app-models-widget-rb']"
      assert_select "[data-role='changed-file']", text: /README.md/
      assert_select "[data-role='changed-file']", text: /app\/models\/widget.rb/
      assert_select "[data-role='comment-trigger']"
      assert_select "[data-role='comment-menu']"
    end
  end

  test "renders a unified files diff when requested" do
    with_sample_repository do |fixture|
      repository = create_local_repository!(fixture)
      pull_request = PullRequest.create!(local_repository: repository, source_branch: "feature", base_branch: "main")

      get repository_pull_files_path(repository, pull_request), params: { layout: "unified" }

      assert_response :success
      assert_select "[data-role='unified-diff']"
      assert_select "[data-role='split-diff']", count: 0
    end
  end

  test "defaults the compare branch away from the base branch when current branch is main" do
    with_sample_repository do |fixture|
      fixture.git("checkout", "main")
      repository = create_local_repository!(fixture)

      get repository_compare_path(repository)

      assert_response :success
      assert_select "select[name='base_branch'] option[selected='selected']", text: "main"
      assert_select "select[name='source_branch'] option[selected='selected']", text: "feature"
    end
  end

  test "updates the pull request description" do
    with_sample_repository do |fixture|
      repository = create_local_repository!(fixture)
      pull_request = PullRequest.create!(local_repository: repository, source_branch: "feature", base_branch: "main", description: "Draft")

      patch repository_pull_path(repository, pull_request), params: {
        pull_request: {
          base_branch: "main",
          description: "Ready to merge once the widget lands."
        }
      }

      assert_redirected_to repository_pull_path(repository, pull_request)
      follow_redirect!
      assert_select "[data-role='conversation-card']", text: /Ready to merge once the widget lands\./
    end
  end

  test "renders markdown on the conversation page" do
    with_sample_repository do |fixture|
      repository = create_local_repository!(fixture)
      pull_request = PullRequest.create!(
        local_repository: repository,
        source_branch: "feature",
        base_branch: "main",
        description: <<~MARKDOWN
          ### Motivation

          Same as [rails#1](https://example.com/rails/1)

          ```
          puts "retry"
          ```

          * [x] Added tests
        MARKDOWN
      )

      get repository_pull_path(repository, pull_request)

      assert_response :success
      assert_select "[data-role='conversation-card'] h3", text: "Motivation"
      assert_select "[data-role='conversation-card'] a[href='https://example.com/rails/1']", text: "rails#1"
      assert_select "[data-role='conversation-card'] pre code", text: /puts "retry"/
      assert_select "[data-role='conversation-card'] input[type='checkbox'][checked='checked'][disabled='disabled']"
    end
  end

  test "updates the pull request title" do
    with_sample_repository do |fixture|
      repository = create_local_repository!(fixture)
      pull_request = PullRequest.create!(local_repository: repository, source_branch: "feature", base_branch: "main")

      patch repository_pull_path(repository, pull_request), params: {
        pull_request: {
          title: "Ship retryable exec_query support",
          base_branch: "main",
          description: ""
        }
      }

      assert_redirected_to repository_pull_path(repository, pull_request)
      follow_redirect!
      assert_select "h1", text: "Ship retryable exec_query support"
      assert_select ".pf-pr-number", text: "##{pull_request.id}"
    end
  end

  test "shows an existing pull request preview instead of allowing a duplicate branch pull request" do
    with_sample_repository do |fixture|
      repository = create_local_repository!(fixture)
      pull_request = PullRequest.create!(
        local_repository: repository,
        source_branch: "feature",
        base_branch: "main",
        description: "Existing review in progress."
      )

      get repository_compare_path(repository), params: {
        source_branch: "feature",
        base_branch: "main"
      }

      assert_response :success
      assert_select "[data-role='existing-pr-preview']", text: /feature/
      assert_select "[data-role='existing-pr-preview']", text: /Existing review in progress\./
      assert_select "a[href='#{repository_pull_path(repository, pull_request)}']", text: "View pull request"
      assert_select "input[type='submit'][value='Create local pull request']", count: 0
    end
  end

  test "redirects duplicate branch creations to the existing pull request" do
    with_sample_repository do |fixture|
      repository = create_local_repository!(fixture)
      pull_request = PullRequest.create!(local_repository: repository, source_branch: "feature", base_branch: "main")

      post repository_pulls_path(repository), params: {
        pull_request: {
          source_branch: "feature",
          base_branch: "main",
          description: "Another description"
        }
      }

      assert_redirected_to repository_pull_path(repository, pull_request)
      assert_equal 1, repository.pull_requests.where(source_branch: "feature").count
    end
  end
end
