class GithubExportsController < ApplicationController
  include RepositoryScoped

  def create
    @pull_request = @local_repository.pull_requests.find(params[:id])
    remote = params[:remote].presence || "origin"
    github_cli = GithubCli.new(repo_path: @local_repository.path, remote:)

    unless GithubCli.available?
      return redirect_to repository_pull_path(@local_repository, @pull_request),
        alert: "GitHub CLI (gh) is not installed. Install it to export PRs to GitHub."
    end

    unless github_cli.has_remote?
      return redirect_to repository_pull_path(@local_repository, @pull_request),
        alert: "Remote \"#{remote}\" not found in this repository."
    end

    existing_url = github_cli.pull_request_for_branch(@pull_request.source_branch)
    if existing_url
      @pull_request.destroy!
      return redirect_to repository_pulls_path(@local_repository),
        notice: "A GitHub PR already exists for this branch: #{existing_url}"
    end

    base = resolve_base_branch(github_cli)
    body = strip_local_image_warning(@pull_request.description)

    begin
      # Push the branch to the remote if it's not already there
      unless github_cli.remote_branch_exists?(@pull_request.source_branch)
        github_cli.push_branch(@pull_request.source_branch)
      end

      pr_url = github_cli.create_pull_request(
        title: @pull_request.title,
        body:,
        base:,
        head: @pull_request.source_branch,
        draft: params[:draft] != "0"
      )

      @pull_request.destroy!

      redirect_to repository_pulls_path(@local_repository),
        notice: "GitHub PR created: <a href=\"#{pr_url}\" target=\"_blank\" rel=\"noopener\">#{pr_url}</a>"
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
