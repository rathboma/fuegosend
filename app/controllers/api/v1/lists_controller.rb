module Api
  module V1
    class ListsController < BaseController
      # GET /api/v1/lists
      def index
        @lists = current_account.lists

        # Paginate
        @lists = paginate(@lists)

        render json: {
          lists: @lists.as_json,
          meta: pagination_meta(@lists)
        }
      end

      # GET /api/v1/lists/:id
      def show
        @list = current_account.lists.find(params[:id])

        render json: {
          list: @list.as_json(
            methods: [:active_subscribers_count],
            include: {
              segments: { only: [:id, :name, :description, :estimated_subscribers_count] }
            }
          )
        }
      end

      # POST /api/v1/lists
      def create
        @list = current_account.lists.build(list_params)

        if @list.save
          render json: {
            list: @list.as_json
          }, status: :created
        else
          render_unprocessable_entity(@list)
        end
      end

      # PATCH/PUT /api/v1/lists/:id
      def update
        @list = current_account.lists.find(params[:id])

        if @list.update(list_params)
          render json: {
            list: @list.as_json
          }
        else
          render_unprocessable_entity(@list)
        end
      end

      # DELETE /api/v1/lists/:id
      def destroy
        @list = current_account.lists.find(params[:id])
        @list.destroy

        head :no_content
      end

      # GET /api/v1/lists/:id/subscribers
      def subscribers
        @list = current_account.lists.find(params[:id])
        @subscribers = @list.active_subscribers

        # Paginate
        @subscribers = paginate(@subscribers)

        render json: {
          subscribers: @subscribers.as_json,
          meta: pagination_meta(@subscribers)
        }
      end

      # POST /api/v1/lists/:id/subscribers
      def add_subscriber
        @list = current_account.lists.find(params[:id])

        # Find or create subscriber
        @subscriber = current_account.subscribers.find_or_create_by!(
          email: params[:email]
        ) do |sub|
          sub.status = "active"
          sub.source = "api"
        end

        # Add to list
        @list.add_subscriber(@subscriber)

        render json: {
          subscriber: @subscriber.as_json,
          message: "Subscriber added to list"
        }
      end

      # DELETE /api/v1/lists/:id/subscribers/:subscriber_id
      def remove_subscriber
        @list = current_account.lists.find(params[:id])
        @subscriber = current_account.subscribers.find(params[:subscriber_id])

        @list.remove_subscriber(@subscriber)

        head :no_content
      end

      private

      def list_params
        params.require(:list).permit(
          :name,
          :description,
          :enable_subscription_form,
          :form_success_message,
          :form_redirect_url,
          :double_opt_in
        )
      end
    end
  end
end
