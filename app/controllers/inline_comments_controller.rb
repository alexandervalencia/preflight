class InlineCommentsController < ApplicationController
  def create
    @local_repository = LocalRepository.find_by!(name: params[:repository_name])
    pull_request = @local_repository.pull_requests.find(params[:pull_request_id])
    comment = pull_request.inline_comments.new(inline_comment_params)

    if comment.save
      redirect_to params[:redirect_to].presence || repository_pull_path(@local_repository, pull_request)
    else
      redirect_to params[:redirect_to].presence || repository_pull_path(@local_repository, pull_request), alert: comment.errors.full_messages.to_sentence
    end
  end

  private

  def inline_comment_params
    params.require(:inline_comment).permit(:commit_sha, :path, :side, :line_number, :body)
  end
end
