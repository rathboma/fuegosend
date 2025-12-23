module Api
  module V1
    class SegmentsController < BaseController
      # GET /api/v1/segments
      def index
        @segments = current_account.segments

        # Filter by list
        if params[:list_id].present?
          @segments = @segments.where(list_id: params[:list_id])
        end

        # Paginate
        @segments = paginate(@segments)

        render json: {
          segments: @segments.as_json,
          meta: pagination_meta(@segments)
        }
      end

      # GET /api/v1/segments/:id
      def show
        @segment = current_account.segments.find(params[:id])

        render json: {
          segment: @segment.as_json(
            include: :list,
            methods: [:current_count]
          )
        }
      end

      # POST /api/v1/segments
      def create
        @segment = current_account.segments.build(segment_params)

        if @segment.save
          # Refresh count in background
          @segment.refresh_count!

          render json: {
            segment: @segment.as_json
          }, status: :created
        else
          render_unprocessable_entity(@segment)
        end
      end

      # PATCH/PUT /api/v1/segments/:id
      def update
        @segment = current_account.segments.find(params[:id])

        if @segment.update(segment_params)
          # Refresh count if criteria changed
          if segment_params[:criteria].present?
            @segment.refresh_count!
          end

          render json: {
            segment: @segment.as_json
          }
        else
          render_unprocessable_entity(@segment)
        end
      end

      # DELETE /api/v1/segments/:id
      def destroy
        @segment = current_account.segments.find(params[:id])
        @segment.destroy

        head :no_content
      end

      # GET /api/v1/segments/:id/subscribers
      def subscribers
        @segment = current_account.segments.find(params[:id])
        @subscribers = @segment.matching_subscribers

        # Paginate
        @subscribers = paginate(@subscribers, per_page: 50)

        render json: {
          subscribers: @subscribers.as_json,
          meta: pagination_meta(@subscribers),
          count: @segment.current_count
        }
      end

      # POST /api/v1/segments/:id/refresh
      def refresh
        @segment = current_account.segments.find(params[:id])
        @segment.refresh_count!

        render json: {
          segment: @segment.as_json,
          message: "Segment count refreshed"
        }
      end

      private

      def segment_params
        params.require(:segment).permit(
          :list_id,
          :name,
          :description,
          criteria: []
        )
      end
    end
  end
end
