module Ses
  class EmailSender
    attr_reader :campaign_send, :campaign, :account, :subscriber, :errors

    def initialize(campaign_send)
      @campaign_send = campaign_send
      @campaign = campaign_send.campaign
      @account = campaign.account
      @subscriber = campaign_send.subscriber
      @errors = []
    end

    def send_email
      # Validate prerequisites
      return failure("Account cannot send emails") unless account.can_send_email?
      return failure("Campaign is not in sending state") unless campaign.sending?
      return failure("Campaign send is not pending") unless campaign_send.status == "pending"

      # Mark as sending
      campaign_send.update!(status: "sending")

      # Prepare email content
      html_body = prepare_html_body
      text_body = prepare_text_body

      # Send via SES
      begin
        send_params = {
          source: "#{campaign.from_name} <#{campaign.from_email}>",
          destination: {
            to_addresses: [subscriber.email]
          },
          message: {
            subject: {
              data: campaign.subject,
              charset: "UTF-8"
            },
            body: {
              html: {
                data: html_body,
                charset: "UTF-8"
              },
              text: {
                data: text_body,
                charset: "UTF-8"
              }
            }
          },
          reply_to_addresses: campaign.reply_to_email.present? ? [campaign.reply_to_email] : []
        }

        # Add configuration set if present (for tracking bounces/complaints)
        if account.respond_to?(:ses_configuration_set_name) && account.ses_configuration_set_name.present?
          send_params[:configuration_set_name] = account.ses_configuration_set_name
        end

        response = ses_client.send_email(send_params)

        # Mark as sent with SES message ID
        campaign_send.mark_sent!(response.message_id)

        # Increment account sent count
        account.increment!(:ses_sent_last_24_hours)

        success(response.message_id)
      rescue Aws::SES::Errors::ServiceError => e
        handle_ses_error(e)
      rescue StandardError => e
        handle_generic_error(e)
      end
    end

    private

    def prepare_html_body
      # Get personalized body from campaign
      body = campaign.personalized_body_for(subscriber)

      # Replace links with tracking URLs
      body = inject_link_tracking(body)

      # Inject open tracking pixel
      body = inject_open_tracking_pixel(body)

      # Ensure unsubscribe link is present
      body = ensure_unsubscribe_link(body)

      body
    end

    def prepare_text_body
      # Convert markdown to HTML first, then strip HTML for plain text
      if campaign.body_markdown.present?
        html = Kramdown::Document.new(campaign.body_markdown).to_html
        text = strip_html(html)
      else
        text = ""
      end

      # Apply merge tags to text version
      text = campaign.send(:apply_merge_tags, text, subscriber)

      # Add unsubscribe link at the bottom
      text += "\n\n---\nUnsubscribe: #{unsubscribe_url}"

      text
    end

    def inject_link_tracking(html)
      # Find all <a> tags and replace href with tracking URL
      html.gsub(/<a\s+([^>]*href=["']([^"']+)["'][^>]*)>/i) do
        full_match = $1
        original_url = $2

        # Skip if already a tracking URL or unsubscribe URL
        next full_match if original_url.include?("/t/c/") || original_url.include?("/unsubscribe")

        # Create or find campaign link
        campaign_link = CampaignLink.find_or_create_for_url(campaign, original_url)
        tracking_url = campaign_link.tracking_url(base_url)

        # Replace the href
        full_match.gsub(original_url, tracking_url)
      end
    end

    def inject_open_tracking_pixel(html)
      # Add 1x1 transparent tracking pixel before closing </body> tag
      pixel = %(<img src="#{open_tracking_url}" width="1" height="1" alt="" style="display:none;" />)

      if html.include?("</body>")
        html.gsub("</body>", "#{pixel}</body>")
      else
        html + pixel
      end
    end

    def ensure_unsubscribe_link(html)
      # Check if unsubscribe link already exists
      return html if html.include?(unsubscribe_url) || html.include?("{{unsubscribe_url}}")

      # Add unsubscribe link at the bottom
      unsubscribe_html = %(<p style="text-align: center; font-size: 12px; color: #999;">
        <a href="#{unsubscribe_url}" style="color: #999; text-decoration: underline;">Unsubscribe</a>
      </p>)

      if html.include?("</body>")
        html.gsub("</body>", "#{unsubscribe_html}</body>")
      else
        html + unsubscribe_html
      end
    end

    def strip_html(html)
      return "" if html.blank?

      # Simple HTML stripping (can use Sanitize gem for better results)
      html.gsub(/<[^>]+>/, " ")
          .gsub(/\s+/, " ")
          .strip
    end

    def base_url
      @base_url ||= Rails.application.config.action_mailer.default_url_options[:host] ||
                    "https://#{account.subdomain}.fuegomail.com"
    end

    def open_tracking_url
      "#{base_url}/t/o/#{tracking_token}"
    end

    def unsubscribe_url
      "#{base_url}/unsubscribe/#{tracking_token}"
    end

    def tracking_token
      @tracking_token ||= generate_tracking_token
    end

    def generate_tracking_token
      # Create a secure token that encodes campaign_send_id
      # We'll use a signed message to prevent tampering
      verifier = Rails.application.message_verifier(:campaign_tracking)
      verifier.generate(campaign_send.id)
    end

    def ses_client
      @ses_client ||= account.ses_client
    end

    def handle_ses_error(error)
      error_message = error.message
      error_code = error.class.name.split("::").last

      @errors << "SES Error (#{error_code}): #{error_message}"

      case error_code
      when "MessageRejected"
        # Permanent failure - mark as failed without retry
        campaign_send.update!(status: "failed")
        failure(error_message)
      when "MailFromDomainNotVerifiedException", "ConfigurationSetDoesNotExistException"
        # Configuration issue - pause campaign
        campaign.pause!(reason: :configuration_error)
        campaign_send.mark_failed!
        failure(error_message)
      when "AccountSendingPausedException"
        # Account paused - pause campaign
        campaign.pause!(reason: :account_paused)
        campaign_send.mark_failed!
        failure(error_message)
      when "ThrottlingException"
        # Rate limited - mark for retry
        campaign_send.mark_failed!(5.minutes)
        failure(error_message)
      else
        # Unknown error - mark for retry with exponential backoff
        retry_delay = calculate_retry_delay
        campaign_send.mark_failed!(retry_delay)
        failure(error_message)
      end
    end

    def handle_generic_error(error)
      @errors << "Error: #{error.class.name} - #{error.message}"

      # Mark for retry
      retry_delay = calculate_retry_delay
      campaign_send.mark_failed!(retry_delay)

      failure(error.message)
    end

    def calculate_retry_delay
      # Exponential backoff: 5min, 15min, 30min, 1hr, 2hr
      case campaign_send.retry_count
      when 0 then 5.minutes
      when 1 then 15.minutes
      when 2 then 30.minutes
      when 3 then 1.hour
      else 2.hours
      end
    end

    def success(message_id)
      {
        success: true,
        message_id: message_id
      }
    end

    def failure(message)
      {
        success: false,
        error: message,
        errors: @errors
      }
    end
  end
end
