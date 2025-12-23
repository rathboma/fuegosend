module Ses
  class RateLimiter
    attr_reader :account

    def initialize(account)
      @account = account
    end

    # Check if we can send an email right now
    def can_send?
      within_per_second_limit? && within_daily_limit?
    end

    # Check if within per-second rate limit
    def within_per_second_limit?
      current_rate < max_send_rate
    end

    # Check if within daily quota
    def within_daily_limit?
      account.ses_sent_last_24_hours < account.ses_max_24_hour_send
    end

    # Get current send rate (emails per second)
    def current_rate
      count = cache_read(rate_key) || 0
      count.to_i
    end

    # Increment the send counter
    def increment!
      # Increment the per-second counter
      current_count = cache_read(rate_key) || 0
      cache_write(rate_key, current_count.to_i + 1, expires_in: 1.second)

      # Note: Daily counter is incremented in EmailSender after successful send
    end

    # Wait time until we can send again (in seconds)
    def wait_time
      if !within_daily_limit?
        # Wait until quota resets (up to 24 hours)
        return time_until_quota_reset
      end

      if !within_per_second_limit?
        # Wait until next second
        return 1
      end

      0
    end

    # Get quota usage percentage
    def quota_usage_percent
      return 0 if account.ses_max_24_hour_send.zero?
      (account.ses_sent_last_24_hours.to_f / account.ses_max_24_hour_send * 100).round(1)
    end

    # Check if quota is nearly exceeded (>80%)
    def quota_nearly_exceeded?
      quota_usage_percent >= 80
    end

    # Check if quota is exceeded
    def quota_exceeded?
      !within_daily_limit?
    end

    # Get remaining sends for today
    def remaining_sends
      [account.ses_max_24_hour_send - account.ses_sent_last_24_hours, 0].max
    end

    # Get remaining capacity in current second
    def remaining_capacity
      [max_send_rate - current_rate, 0].max
    end

    # Reset the per-second counter (mainly for testing)
    def reset_per_second!
      cache_delete(rate_key)
    end

    private

    def max_send_rate
      account.ses_max_send_rate || 14 # Default to AWS free tier limit
    end

    def rate_key
      # Key format: ses_rate:account_id:timestamp
      # Using second-level precision
      "ses_rate:#{account.id}:#{Time.current.to_i}"
    end

    def time_until_quota_reset
      # SES quotas reset after 24 hours
      # We track this in ses_quota_reset_at
      return 24.hours if account.ses_quota_reset_at.blank?

      reset_time = account.ses_quota_reset_at
      time_diff = reset_time - Time.current

      # If reset time has passed, quota should have been refreshed
      # Return 0 to allow retry
      time_diff > 0 ? time_diff : 0
    end

    # Cache helpers (use Rails.cache which points to Solid Cache/SQLite)
    def cache_read(key)
      Rails.cache.read(key)
    end

    def cache_write(key, value, options = {})
      Rails.cache.write(key, value, options)
    end

    def cache_delete(key)
      Rails.cache.delete(key)
    end
  end
end
