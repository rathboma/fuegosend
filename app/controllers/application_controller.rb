class ApplicationController < ActionController::Base
  # Only allow modern browsers supporting webp images, web push, badges, import maps, CSS nesting, and CSS :has.
  allow_browser versions: :modern

  # Changes to the importmap will invalidate the etag for HTML responses
  stale_when_importmap_changes

  before_action :ensure_setup_complete

  private

  def ensure_setup_complete
    return unless user_signed_in?
    return if controller_name == 'setup' || devise_controller?
    return if current_user.account.setup_complete?

    redirect_to setup_path, alert: "Please complete your account setup to continue."
  end
end
