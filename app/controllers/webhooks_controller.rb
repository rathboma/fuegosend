class WebhooksController < ApplicationController
  # Skip CSRF protection for webhook endpoints
  skip_before_action :verify_authenticity_token

  # SNS endpoint for receiving SES notifications
  def sns
    # Parse the SNS message
    sns_message = parse_sns_message

    unless sns_message
      render json: { error: "Invalid SNS message" }, status: :bad_request
      return
    end

    # Handle SNS subscription confirmation
    if sns_message[:message_type] == "SubscriptionConfirmation"
      handle_subscription_confirmation(sns_message)
      render json: { message: "Subscription confirmed" }, status: :ok
      return
    end

    # Handle SNS notification
    if sns_message[:message_type] == "Notification"
      handle_notification(sns_message)
      render json: { message: "Notification received" }, status: :ok
      return
    end

    # Unknown message type
    render json: { error: "Unknown message type" }, status: :bad_request
  end

  private

  def parse_sns_message
    begin
      # AWS SNS sends the message in the request body as JSON
      body = request.body.read
      message = JSON.parse(body, symbolize_names: true)

      # Verify required SNS fields are present
      required_fields = [:Type, :MessageId, :TopicArn, :Message]
      return nil unless required_fields.all? { |field| message.key?(field) }

      {
        message_type: message[:Type],
        message_id: message[:MessageId],
        topic_arn: message[:TopicArn],
        timestamp: message[:Timestamp],
        signature: message[:Signature],
        signing_cert_url: message[:SigningCertURL],
        message: message[:Message],
        subscribe_url: message[:SubscribeURL],
        raw: message
      }
    rescue JSON::ParserError => e
      Rails.logger.error("[WebhooksController] Failed to parse SNS message: #{e.message}")
      nil
    end
  end

  def handle_subscription_confirmation(sns_message)
    # Automatically confirm SNS subscription by visiting the SubscribeURL
    subscribe_url = sns_message[:subscribe_url]

    if subscribe_url
      begin
        # Make HTTP GET request to confirm subscription
        uri = URI(subscribe_url)
        Net::HTTP.get(uri)

        Rails.logger.info("[WebhooksController] SNS subscription confirmed: #{sns_message[:topic_arn]}")
      rescue StandardError => e
        Rails.logger.error("[WebhooksController] Failed to confirm SNS subscription: #{e.message}")
      end
    end
  end

  def handle_notification(sns_message)
    begin
      # Parse the nested SES message from the SNS message
      ses_message = JSON.parse(sns_message[:message], symbolize_names: true)

      # Determine the event type
      event_type = determine_event_type(ses_message)

      unless event_type
        Rails.logger.warn("[WebhooksController] Unknown SES event type: #{ses_message.keys.join(', ')}")
        return
      end

      # Find the account based on the topic ARN or other identifiers
      account = find_account_for_notification(sns_message, ses_message)

      unless account
        Rails.logger.error("[WebhooksController] Could not find account for notification")
        return
      end

      # Create webhook event record
      webhook_event = account.webhook_events.create!(
        event_type: event_type,
        payload: ses_message.to_json,
        processed: false
      )

      # Enqueue processing job
      Webhooks::ProcessSnsNotificationJob.set(queue: :webhooks)
                                         .perform_later(webhook_event.id)

      Rails.logger.info("[WebhooksController] Webhook event #{webhook_event.id} created for account #{account.id}")
    rescue JSON::ParserError => e
      Rails.logger.error("[WebhooksController] Failed to parse SES message: #{e.message}")
    rescue StandardError => e
      Rails.logger.error("[WebhooksController] Error handling notification: #{e.message}")
    end
  end

  def determine_event_type(ses_message)
    # SES sends different message structures for different event types
    if ses_message[:eventType]
      # SNS Configuration Set events use eventType
      case ses_message[:eventType]
      when "Bounce"
        "bounce"
      when "Complaint"
        "complaint"
      when "Delivery"
        "delivery"
      when "Send"
        "send"
      when "Reject"
        "reject"
      when "Open"
        "open"
      when "Click"
        "click"
      else
        nil
      end
    elsif ses_message[:notificationType]
      # Classic SNS topics use notificationType
      case ses_message[:notificationType]
      when "Bounce"
        "bounce"
      when "Complaint"
        "complaint"
      when "Delivery"
        "delivery"
      else
        nil
      end
    else
      nil
    end
  end

  def find_account_for_notification(sns_message, ses_message)
    # Strategy 1: Try to find account by matching topic ARN with webhook_endpoints
    topic_arn = sns_message[:topic_arn]
    if topic_arn
      webhook_endpoint = WebhookEndpoint.find_by(sns_topic_arn: topic_arn)
      return webhook_endpoint.account if webhook_endpoint
    end

    # Strategy 2: Extract message ID and find campaign_send
    # This works for delivery, bounce, and complaint notifications
    message_id = extract_message_id(ses_message)
    if message_id
      campaign_send = CampaignSend.find_by(ses_message_id: message_id)
      return campaign_send.campaign.account if campaign_send
    end

    # Strategy 3: Extract email address and find subscriber
    email = extract_email_address(ses_message)
    if email
      subscriber = Subscriber.find_by(email: email)
      return subscriber.account if subscriber
    end

    # Could not determine account
    nil
  end

  def extract_message_id(ses_message)
    # Different paths for different message structures
    ses_message.dig(:mail, :messageId) ||
      ses_message.dig(:bounce, :feedbackId) ||
      ses_message.dig(:complaint, :feedbackId)
  end

  def extract_email_address(ses_message)
    # Try to get destination email
    destination = ses_message.dig(:mail, :destination)
    return destination.first if destination.is_a?(Array) && destination.any?

    # Try bounce recipients
    bounce_recipients = ses_message.dig(:bounce, :bouncedRecipients)
    return bounce_recipients.first[:emailAddress] if bounce_recipients.is_a?(Array) && bounce_recipients.any?

    # Try complaint recipients
    complaint_recipients = ses_message.dig(:complaint, :complainedRecipients)
    return complaint_recipients.first[:emailAddress] if complaint_recipients.is_a?(Array) && complaint_recipients.any?

    nil
  end
end
