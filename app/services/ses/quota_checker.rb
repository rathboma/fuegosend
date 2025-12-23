module Ses
  class QuotaChecker
    attr_reader :account, :errors

    def initialize(account)
      @account = account
      @errors = []
    end

    # Refresh SES quota from AWS API
    def refresh_quota!
      begin
        response = ses_client.get_send_quota

        # Update account with fresh quota data
        account.update!(
          ses_max_send_rate: response.max_send_rate.to_i,
          ses_max_24_hour_send: response.max_24_hour_send.to_i,
          ses_sent_last_24_hours: response.sent_last_24_hours.to_i,
          ses_quota_reset_at: 24.hours.from_now
        )

        success(response)
      rescue Aws::SES::Errors::ServiceError => e
        handle_error(e)
        failure(e.message)
      rescue StandardError => e
        handle_error(e)
        failure(e.message)
      end
    end

    # Check account sending statistics
    def get_send_statistics
      begin
        response = ses_client.get_send_statistics

        # Returns an array of data points for the last two weeks
        # Each data point includes: timestamp, delivery_attempts, bounces, complaints, rejects
        {
          success: true,
          data_points: response.send_data_points.map do |point|
            {
              timestamp: point.timestamp,
              delivery_attempts: point.delivery_attempts,
              bounces: point.bounces,
              complaints: point.complaints,
              rejects: point.rejects
            }
          end
        }
      rescue Aws::SES::Errors::ServiceError => e
        handle_error(e)
        failure(e.message)
      rescue StandardError => e
        handle_error(e)
        failure(e.message)
      end
    end

    # Test SES connection and credentials
    def test_connection
      begin
        # Try to get send quota as a simple connection test
        response = ses_client.get_send_quota

        success({
          connected: true,
          max_send_rate: response.max_send_rate,
          max_24_hour_send: response.max_24_hour_send,
          sent_last_24_hours: response.sent_last_24_hours
        })
      rescue Aws::SES::Errors::ServiceError => e
        handle_error(e)
        failure("SES connection failed: #{e.message}")
      rescue StandardError => e
        handle_error(e)
        failure("Connection failed: #{e.message}")
      end
    end

    # Check if account is in sandbox mode
    def check_sandbox_status
      begin
        response = ses_client.get_account_sending_enabled

        # If we can successfully call this, check the response
        # Note: In sandbox mode, you can only send to verified email addresses
        {
          success: true,
          sending_enabled: response.enabled,
          message: response.enabled ? "Account is production mode" : "Account sending is disabled"
        }
      rescue Aws::SES::Errors::ServiceError => e
        handle_error(e)
        failure(e.message)
      rescue StandardError => e
        handle_error(e)
        failure(e.message)
      end
    end

    # Get account reputation metrics
    def get_reputation_metrics
      begin
        # Note: This requires CloudWatch access
        # For now, we'll use send statistics as a proxy for reputation

        stats = get_send_statistics

        if stats[:success]
          recent_data = stats[:data_points].last(10) # Last 10 data points

          total_attempts = recent_data.sum { |dp| dp[:delivery_attempts] }
          total_bounces = recent_data.sum { |dp| dp[:bounces] }
          total_complaints = recent_data.sum { |dp| dp[:complaints] }

          bounce_rate = total_attempts > 0 ? (total_bounces.to_f / total_attempts * 100).round(2) : 0
          complaint_rate = total_attempts > 0 ? (total_complaints.to_f / total_attempts * 100).round(2) : 0

          {
            success: true,
            bounce_rate: bounce_rate,
            complaint_rate: complaint_rate,
            total_attempts: total_attempts,
            total_bounces: total_bounces,
            total_complaints: total_complaints,
            health_status: determine_health_status(bounce_rate, complaint_rate)
          }
        else
          stats
        end
      rescue StandardError => e
        handle_error(e)
        failure(e.message)
      end
    end

    private

    def ses_client
      @ses_client ||= account.ses_client
    end

    def determine_health_status(bounce_rate, complaint_rate)
      # AWS SES thresholds:
      # - Bounce rate should be below 5%
      # - Complaint rate should be below 0.1%

      if bounce_rate > 10 || complaint_rate > 0.5
        "critical" # Very high rates, risk of suspension
      elsif bounce_rate > 5 || complaint_rate > 0.1
        "warning" # Above AWS thresholds
      else
        "healthy" # Within acceptable limits
      end
    end

    def handle_error(error)
      error_message = error.message
      error_class = error.class.name

      @errors << "#{error_class}: #{error_message}"

      # Log error for monitoring
      Rails.logger.error("[SES QuotaChecker] Account #{account.id}: #{error_class} - #{error_message}")
    end

    def success(data)
      {
        success: true,
        data: data,
        account_id: account.id
      }
    end

    def failure(message)
      {
        success: false,
        error: message,
        errors: @errors,
        account_id: account.id
      }
    end
  end
end
