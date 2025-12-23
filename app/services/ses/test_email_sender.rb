module Ses
  class TestEmailSender
    attr_reader :campaign, :recipient_email, :account, :errors

    def initialize(campaign, recipient_email)
      @campaign = campaign
      @recipient_email = recipient_email
      @account = campaign.account
      @errors = []
    end

    def send_email
      # Validate prerequisites
      return failure("Account cannot send emails") unless account.can_send_email?
      return failure("Campaign must have content") if campaign.body_markdown.blank?
      return failure("Campaign must have a template") if campaign.template.blank?
      return failure("Invalid email address") unless valid_email?(recipient_email)

      # Create a sample subscriber for rendering
      sample_subscriber = build_sample_subscriber

      # Prepare email content (without tracking)
      html_body = prepare_html_body(sample_subscriber)
      text_body = prepare_text_body(sample_subscriber)

      # Send via SES
      begin
        send_params = {
          source: "#{campaign.from_name} <#{campaign.from_email}>",
          destination: {
            to_addresses: [recipient_email]
          },
          message: {
            subject: {
              data: "[TEST] #{campaign.subject}",
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

        response = ses_client.send_email(send_params)

        success(response.message_id)
      rescue Aws::SES::Errors::ServiceError => e
        handle_ses_error(e)
      rescue StandardError => e
        handle_generic_error(e)
      end
    end

    private

    def build_sample_subscriber
      # Try to use first subscriber from the campaign's list, or create a mock one
      first_subscriber = campaign.list.subscribers.first

      if first_subscriber
        first_subscriber
      else
        # Create a mock subscriber object (not persisted)
        Subscriber.new(
          email: recipient_email,
          custom_attributes: {
            'name' => 'Test User',
            'first_name' => 'Test',
            'last_name' => 'User'
          }
        )
      end
    end

    def prepare_html_body(subscriber)
      # Render the campaign through the template
      # This uses the template's render_for method which applies Mustache
      html = campaign.template.render_for(subscriber, campaign)

      # Add test email notice at the top
      test_notice = <<~HTML
        <div style="background-color: #fff3cd; border: 2px solid #ffc107; padding: 12px; margin: 20px; text-align: center; border-radius: 4px;">
          <strong>⚠️ TEST EMAIL</strong> - This is a preview of how your campaign will look to subscribers.
        </div>
      HTML

      # Inject after opening body tag or at the beginning
      if html.include?("<body")
        html.sub(/(<body[^>]*>)/i, "\\1#{test_notice}")
      else
        test_notice + html
      end
    end

    def prepare_text_body(subscriber)
      # Convert markdown to text
      if campaign.body_markdown.present?
        html = Kramdown::Document.new(campaign.body_markdown).to_html
        text = strip_html(html)
      else
        text = ""
      end

      # Apply merge tags
      data = campaign.send(:build_mustache_data, subscriber)
      data.each do |key, value|
        text = text.gsub("{{#{key}}}", value.to_s)
      end

      # Add test email notice
      notice = "=" * 60 + "\n"
      notice += "⚠️  TEST EMAIL - This is a preview of your campaign\n"
      notice += "=" * 60 + "\n\n"

      notice + text
    end

    def strip_html(html)
      return "" if html.blank?

      html.gsub(/<[^>]+>/, " ")
          .gsub(/\s+/, " ")
          .strip
    end

    def valid_email?(email)
      email.present? && email.match?(URI::MailTo::EMAIL_REGEXP)
    end

    def ses_client
      @ses_client ||= account.ses_client
    end

    def handle_ses_error(error)
      error_message = error.message
      error_code = error.class.name.split("::").last

      @errors << "SES Error (#{error_code}): #{error_message}"
      failure(error_message)
    end

    def handle_generic_error(error)
      @errors << "Error: #{error.class.name} - #{error.message}"
      failure(error.message)
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
