module Api
  module V1
    class CampaignsController < BaseController
      # GET /api/v1/campaigns
      def index
        @campaigns = current_account.campaigns

        # Filter by status
        if params[:status].present?
          @campaigns = @campaigns.where(status: params[:status])
        end

        # Filter by list
        if params[:list_id].present?
          @campaigns = @campaigns.where(list_id: params[:list_id])
        end

        # Paginate
        @campaigns = paginate(@campaigns)

        render json: {
          campaigns: @campaigns.as_json(
            include: { list: { only: [:id, :name] } },
            methods: [:percent_complete, :open_rate, :click_rate, :bounce_rate]
          ),
          meta: pagination_meta(@campaigns)
        }
      end

      # GET /api/v1/campaigns/:id
      def show
        @campaign = current_account.campaigns.find(params[:id])

        render json: {
          campaign: @campaign.as_json(
            include: {
              list: { only: [:id, :name] },
              segment: { only: [:id, :name] },
              template: { only: [:id, :name] }
            },
            methods: [
              :percent_complete,
              :open_rate,
              :click_rate,
              :bounce_rate,
              :failure_rate,
              :current_send_rate
            ]
          )
        }
      end

      # POST /api/v1/campaigns
      def create
        @campaign = current_account.campaigns.build(campaign_params)
        @campaign.status = "draft"

        if @campaign.save
          render json: {
            campaign: @campaign.as_json
          }, status: :created
        else
          render_unprocessable_entity(@campaign)
        end
      end

      # PATCH/PUT /api/v1/campaigns/:id
      def update
        @campaign = current_account.campaigns.find(params[:id])

        # Only allow updating draft campaigns
        unless @campaign.draft?
          render_error("Can only update draft campaigns", status: :unprocessable_entity)
          return
        end

        if @campaign.update(campaign_params)
          render json: {
            campaign: @campaign.as_json
          }
        else
          render_unprocessable_entity(@campaign)
        end
      end

      # DELETE /api/v1/campaigns/:id
      def destroy
        @campaign = current_account.campaigns.find(params[:id])

        # Only allow deleting draft campaigns
        unless @campaign.draft?
          render_error("Can only delete draft campaigns", status: :unprocessable_entity)
          return
        end

        @campaign.destroy
        head :no_content
      end

      # POST /api/v1/campaigns/:id/schedule
      def schedule
        @campaign = current_account.campaigns.find(params[:id])

        scheduled_time = params[:scheduled_at].present? ? Time.parse(params[:scheduled_at]) : Time.current

        if @campaign.schedule!(scheduled_time)
          render json: {
            campaign: @campaign.as_json,
            message: "Campaign scheduled successfully"
          }
        else
          render_error("Failed to schedule campaign", status: :unprocessable_entity)
        end
      end

      # POST /api/v1/campaigns/:id/send
      def send_now
        @campaign = current_account.campaigns.find(params[:id])

        if @campaign.start_sending!
          render json: {
            campaign: @campaign.as_json,
            message: "Campaign sending started"
          }
        else
          render_error("Failed to start campaign", status: :unprocessable_entity)
        end
      end

      # POST /api/v1/campaigns/:id/pause
      def pause
        @campaign = current_account.campaigns.find(params[:id])

        if @campaign.pause!
          render json: {
            campaign: @campaign.as_json,
            message: "Campaign paused successfully"
          }
        else
          render_error("Failed to pause campaign", status: :unprocessable_entity)
        end
      end

      # POST /api/v1/campaigns/:id/resume
      def resume
        @campaign = current_account.campaigns.find(params[:id])

        if @campaign.resume!
          render json: {
            campaign: @campaign.as_json,
            message: "Campaign resumed successfully"
          }
        else
          render_error("Failed to resume campaign", status: :unprocessable_entity)
        end
      end

      # POST /api/v1/campaigns/:id/cancel
      def cancel
        @campaign = current_account.campaigns.find(params[:id])

        if @campaign.cancel!
          render json: {
            campaign: @campaign.as_json,
            message: "Campaign cancelled successfully"
          }
        else
          render_error("Failed to cancel campaign", status: :unprocessable_entity)
        end
      end

      # GET /api/v1/campaigns/:id/stats
      def stats
        @campaign = current_account.campaigns.find(params[:id])

        render json: {
          stats: {
            status: @campaign.status,
            total_recipients: @campaign.total_recipients,
            sent_count: @campaign.sent_count,
            delivered_count: @campaign.delivered_count,
            bounced_count: @campaign.bounced_count,
            complained_count: @campaign.complained_count,
            opened_count: @campaign.opened_count,
            clicked_count: @campaign.clicked_count,
            unsubscribed_count: @campaign.unsubscribed_count,
            percent_complete: @campaign.percent_complete,
            open_rate: @campaign.open_rate,
            click_rate: @campaign.click_rate,
            bounce_rate: @campaign.bounce_rate,
            failure_rate: @campaign.failure_rate,
            current_send_rate: @campaign.current_send_rate,
            started_at: @campaign.started_sending_at,
            finished_at: @campaign.finished_sending_at
          }
        }
      end

      private

      def campaign_params
        params.require(:campaign).permit(
          :list_id,
          :segment_id,
          :template_id,
          :name,
          :subject,
          :from_name,
          :from_email,
          :reply_to_email,
          :body_markdown
        )
      end
    end
  end
end
