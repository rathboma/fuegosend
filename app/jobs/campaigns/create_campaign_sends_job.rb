class Campaigns::CreateCampaignSendsJob < ApplicationJob
  queue_as :default

  def perform(campaign_id)
    campaign = Campaign.find(campaign_id)

    # Get total count first
    total_count = campaign.recipients.count
    campaign.update!(
      total_recipients: total_count,
      sends_created_count: 0,
      preparation_progress: 0
    )

    created_count = 0
    batch_size = 1000

    # Create campaign sends in batches with progress updates
    campaign.recipients.find_each(batch_size: batch_size) do |subscriber|
      campaign.campaign_sends.create!(subscriber: subscriber)
      created_count += 1

      # Update progress every 100 records or at the end of each batch
      if created_count % 100 == 0 || created_count == total_count
        progress = ((created_count.to_f / total_count) * 100).round
        campaign.update_columns(
          sends_created_count: created_count,
          preparation_progress: progress
        )
      end
    end

    # Ensure we're at 100% at the end
    campaign.update_columns(
      sends_created_count: total_count,
      preparation_progress: 100
    )

    Rails.logger.info "Created #{total_count} campaign sends for campaign #{campaign.id}"

    # Trigger next step in workflow based on campaign status
    campaign.reload
    case campaign.status
    when "queued_for_review"
      # Continue with sandbox workflow
      campaign.continue_after_preparation!
    when "sending"
      # Notify and start enqueueing sends
      campaign.notify_sending_started!
      Campaigns::EnqueueSendingJob.perform_later(campaign.id)
    end
  rescue => e
    Rails.logger.error "Failed to create campaign sends for campaign #{campaign.id}: #{e.message}"
    raise
  end
end
