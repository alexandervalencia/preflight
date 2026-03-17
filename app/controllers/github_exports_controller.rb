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
