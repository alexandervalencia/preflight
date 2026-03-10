class ApplicationController < ActionController::Base
  # Only allow modern browsers supporting webp images, web push, badges, import maps, CSS nesting, and CSS :has.
  allow_browser versions: :modern

  private

  def comments_by_key(comments)
    comments.group_by { |comment| [comment.path, comment.side, comment.line_number] }
  end
end
