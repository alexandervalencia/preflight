class ApplicationController < ActionController::Base
  # Only allow modern browsers supporting webp images, web push, badges, import maps, CSS nesting, and CSS :has.
  allow_browser versions: :modern

  private

  def diff_preference(key)
    params[key].presence || cookies["pf_#{key}"]
  end
end
