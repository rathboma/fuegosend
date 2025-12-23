class TrackingController < ApplicationController
  # Skip CSRF protection for tracking endpoints
  skip_before_action :verify_authenticity_token

  # Track email opens via 1x1 transparent tracking pixel
  # GET /t/o/:token
  def open
    campaign_send = find_campaign_send_by_token(params[:token])

    if campaign_send
      # Track the open
      campaign_send.track_open!

      Rails.logger.info("[TrackingController] Open tracked for CampaignSend #{campaign_send.id}")
    else
      Rails.logger.warn("[TrackingController] Invalid open tracking token: #{params[:token]}")
    end

    # Return 1x1 transparent GIF
    send_tracking_pixel
  end

  # Track link clicks and redirect to original URL
  # GET /t/c/:token
  def click
    campaign_link = CampaignLink.find_by(token: params[:token])

    unless campaign_link
      Rails.logger.warn("[TrackingController] Invalid click tracking token: #{params[:token]}")
      render plain: "Invalid link", status: :not_found
      return
    end

    # Get campaign_send from query parameters if present
    # The email should include campaign_send info in the tracking URL
    campaign_send_id = params[:cs]
    campaign_send = campaign_link.campaign.campaign_sends.find_by(id: campaign_send_id) if campaign_send_id

    if campaign_send
      # Track the click with IP and user agent
      campaign_link.track_click!(
        campaign_send,
        ip_address: request.remote_ip,
        user_agent: request.user_agent
      )

      # Also track on the campaign_send
      campaign_send.track_click!(campaign_link)

      Rails.logger.info("[TrackingController] Click tracked for CampaignLink #{campaign_link.id}, CampaignSend #{campaign_send.id}")
    else
      # Still track the click but without campaign_send association
      # This can happen if the tracking token is shared
      Rails.logger.warn("[TrackingController] Click tracked without campaign_send for CampaignLink #{campaign_link.id}")
    end

    # Redirect to the original URL
    redirect_to campaign_link.original_url, allow_other_host: true
  end

  private

  def find_campaign_send_by_token(token)
    # Decode the signed token to get campaign_send_id
    begin
      verifier = Rails.application.message_verifier(:campaign_tracking)
      campaign_send_id = verifier.verify(token)
      CampaignSend.find_by(id: campaign_send_id)
    rescue ActiveSupport::MessageVerifier::InvalidSignature
      Rails.logger.error("[TrackingController] Invalid tracking token signature")
      nil
    rescue StandardError => e
      Rails.logger.error("[TrackingController] Error decoding token: #{e.message}")
      nil
    end
  end

  def send_tracking_pixel
    # Send a 1x1 transparent GIF
    pixel_data = Base64.decode64(
      "R0lGODlhAQABAIAAAAAAAP///yH5BAEAAAAALAAAAAABAAEAAAIBRAA7"
    )

    send_data pixel_data,
              type: "image/gif",
              disposition: "inline",
              filename: "pixel.gif"
  end
end
