module ApiAuthenticable
  extend ActiveSupport::Concern

  included do
    before_action :authenticate_with_api_key!
    skip_before_action :verify_authenticity_token
  end

  private

  def authenticate_with_api_key!
    token = extract_token_from_header

    unless token
      render_unauthorized("Missing API token")
      return
    end

    @current_api_key = ApiKey.authenticate(token)

    unless @current_api_key
      render_unauthorized("Invalid API token")
      return
    end

    # Check if API key is expired
    if @current_api_key.expires_at.present? && @current_api_key.expires_at < Time.current
      render_unauthorized("API token expired")
      return
    end

    # Touch last_used_at timestamp
    @current_api_key.touch_last_used!

    # Set current account from API key
    @current_account = @current_api_key.account
  end

  def extract_token_from_header
    # Extract Bearer token from Authorization header
    # Format: "Authorization: Bearer <token>"
    auth_header = request.headers["Authorization"]
    return nil unless auth_header

    auth_header.sub(/^Bearer\s+/, "")
  end

  def current_api_key
    @current_api_key
  end

  def current_account
    @current_account
  end

  def current_user
    @current_api_key&.user
  end

  def render_unauthorized(message = "Unauthorized")
    render json: {
      error: message,
      status: 401
    }, status: :unauthorized
  end

  def render_forbidden(message = "Forbidden")
    render json: {
      error: message,
      status: 403
    }, status: :forbidden
  end

  def render_not_found(message = "Not found")
    render json: {
      error: message,
      status: 404
    }, status: :not_found
  end

  def render_unprocessable_entity(resource)
    render json: {
      error: "Validation failed",
      errors: resource.errors.full_messages,
      status: 422
    }, status: :unprocessable_entity
  end

  def render_error(message, status: :internal_server_error)
    render json: {
      error: message,
      status: Rack::Utils::SYMBOL_TO_STATUS_CODE[status]
    }, status: status
  end
end
