class ApplicationController < ActionController::Base
  # Only allow modern browsers supporting webp images, web push, badges, import maps, CSS nesting, and CSS :has.
  allow_browser versions: :modern

  helper_method :diff_preference

  private

  def diff_preference(key)
    params[key].presence || cookies["pf_#{key}"]
  end
end
