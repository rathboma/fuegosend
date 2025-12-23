class SubscriptionsController < ApplicationController
  # Use subscription form layout for public pages
  layout "subscription_form", only: [:new, :confirm]

  # Skip CSRF protection for unsubscribe endpoints
  skip_before_action :verify_authenticity_token, only: [:unsubscribe_confirm]

  # Show unsubscribe confirmation page
  # GET /unsubscribe/:token
  def unsubscribe
    @campaign_send = find_campaign_send_by_token(params[:token])

    unless @campaign_send
      render plain: "Invalid unsubscribe link", status: :not_found
      return
    end

    @subscriber = @campaign_send.subscriber
    @campaign = @campaign_send.campaign

    # Check if already unsubscribed
    if @campaign_send.unsubscribed_at.present?
      @already_unsubscribed = true
    end
  end

  # Process unsubscribe confirmation
  # POST /unsubscribe/:token
  def unsubscribe_confirm
    campaign_send = find_campaign_send_by_token(params[:token])

    unless campaign_send
      render plain: "Invalid unsubscribe link", status: :not_found
      return
    end

    subscriber = campaign_send.subscriber

    # Track unsubscribe on campaign_send
    campaign_send.track_unsubscribe!

    Rails.logger.info("[SubscriptionsController] Subscriber #{subscriber.id} unsubscribed via campaign #{campaign_send.campaign_id}")

    # Redirect to confirmation page or show success message
    @subscriber = subscriber
    @unsubscribed = true
    render :unsubscribe
  end

  # Public subscription form (for Phase 7)
  # GET /subscribe/:list_id
  def new
    @list = List.find_by(id: params[:list_id])

    unless @list && @list.enable_subscription_form
      render plain: "Subscription form not available", status: :not_found
      return
    end

    @account = @list.account
    @subscriber = Subscriber.new
  end

  # Process subscription form submission (for Phase 7)
  # POST /subscribe/:list_id
  def create
    @list = List.find_by(id: params[:list_id])

    unless @list && @list.enable_subscription_form
      render plain: "Subscription form not available", status: :not_found
      return
    end

    @account = @list.account

    # Find or create subscriber
    @subscriber = @account.subscribers.find_or_initialize_by(email: subscription_params[:email])

    # Set attributes from form (using ActiveRecord assign_attributes)
    @subscriber.assign_attributes(subscription_params.except(:custom_attributes))

    # Set custom attributes if provided
    if params[:custom_attributes]
      custom_attrs = @subscriber.custom_attributes || {}
      params[:custom_attributes].each do |key, value|
        custom_attrs[key] = value if value.present?
      end
      @subscriber.custom_attributes = custom_attrs
    end

    # Set source
    @subscriber.source ||= "subscription_form"
    @subscriber.ip_address ||= request.remote_ip

    if @subscriber.save
      # Add to list
      @list.add_subscriber(@subscriber)

      # If double opt-in is enabled, send confirmation email
      if @list.double_opt_in && @subscriber.confirmed_at.nil?
        SubscriptionMailer.confirm_subscription(@subscriber, @list).deliver_later
        @pending_confirmation = true
      else
        @subscriber.update(confirmed_at: Time.current)
      end

      # Redirect or show success message
      if @list.form_redirect_url.present?
        redirect_to @list.form_redirect_url, allow_other_host: true
      else
        @success = true
        render :new
      end
    else
      # Re-render form with errors
      render :new, status: :unprocessable_entity
    end
  end

  # Confirm subscription via email link (double opt-in)
  # GET /confirm_subscription/:token
  def confirm
    token = params[:token]

    begin
      verifier = Rails.application.message_verifier(:subscription_confirmation)
      data = verifier.verify(token)
      subscriber_id = data[:subscriber_id]
      list_id = data[:list_id]
    rescue ActiveSupport::MessageVerifier::InvalidSignature
      render plain: "Invalid confirmation link", status: :not_found
      return
    end

    @subscriber = Subscriber.find_by(id: subscriber_id)
    @list = List.find_by(id: list_id)

    unless @subscriber && @list
      render plain: "Invalid confirmation link", status: :not_found
      return
    end

    # Check if already confirmed
    if @subscriber.confirmed_at.present?
      # Already confirmed, just show success
      render :confirm
      return
    end

    # Confirm the subscriber
    @subscriber.update!(confirmed_at: Time.current, status: "active")

    Rails.logger.info("[SubscriptionsController] Subscriber #{@subscriber.id} confirmed subscription to list #{@list.id}")

    render :confirm
  end

  private

  def find_campaign_send_by_token(token)
    begin
      verifier = Rails.application.message_verifier(:campaign_tracking)
      campaign_send_id = verifier.verify(token)
      CampaignSend.find_by(id: campaign_send_id)
    rescue ActiveSupport::MessageVerifier::InvalidSignature
      Rails.logger.error("[SubscriptionsController] Invalid unsubscribe token signature")
      nil
    rescue StandardError => e
      Rails.logger.error("[SubscriptionsController] Error decoding token: #{e.message}")
      nil
    end
  end

  def subscription_params
    params.require(:subscriber).permit(:email, :first_name, :last_name)
  end
end
