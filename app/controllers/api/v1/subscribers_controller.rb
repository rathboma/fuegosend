module Api
  module V1
    class SubscribersController < BaseController
      # GET /api/v1/subscribers
      def index
        @subscribers = current_account.subscribers

        # Filter by status
        if params[:status].present?
          @subscribers = @subscribers.where(status: params[:status])
        end

        # Filter by list
        if params[:list_id].present?
          list = current_account.lists.find(params[:list_id])
          @subscribers = @subscribers.joins(:list_subscriptions)
                                     .where(list_subscriptions: { list_id: list.id, status: "active" })
        end

        # Search by email
        if params[:email].present?
          @subscribers = @subscribers.where("email LIKE ?", "%#{params[:email]}%")
        end

        # Paginate
        @subscribers = paginate(@subscribers)

        render json: {
          subscribers: @subscribers.as_json(include: :list_subscriptions),
          meta: pagination_meta(@subscribers)
        }
      end

      # GET /api/v1/subscribers/:id
      def show
        @subscriber = current_account.subscribers.find(params[:id])

        render json: {
          subscriber: @subscriber.as_json(
            include: {
              list_subscriptions: { include: :list }
            }
          )
        }
      end

      # POST /api/v1/subscribers
      def create
        @subscriber = current_account.subscribers.find_or_initialize_by(
          email: subscriber_params[:email]
        )

        @subscriber.assign_attributes(subscriber_params.except(:email, :list_ids, :custom_attributes))

        # Merge custom attributes
        if params[:custom_attributes]
          existing_attrs = @subscriber.custom_attributes || {}
          @subscriber.custom_attributes = existing_attrs.merge(params[:custom_attributes])
        end

        # Set source if not provided
        @subscriber.source ||= "api"
        @subscriber.status ||= "active"

        if @subscriber.save
          # Add to lists if specified
          if params[:list_ids].present?
            params[:list_ids].each do |list_id|
              list = current_account.lists.find(list_id)
              list.add_subscriber(@subscriber)
            end
          end

          render json: {
            subscriber: @subscriber.as_json(include: :list_subscriptions)
          }, status: :created
        else
          render_unprocessable_entity(@subscriber)
        end
      end

      # PATCH/PUT /api/v1/subscribers/:id
      def update
        @subscriber = current_account.subscribers.find(params[:id])

        # Update attributes
        @subscriber.assign_attributes(subscriber_params.except(:email, :list_ids, :custom_attributes))

        # Merge custom attributes
        if params[:custom_attributes]
          existing_attrs = @subscriber.custom_attributes || {}
          @subscriber.custom_attributes = existing_attrs.merge(params[:custom_attributes])
        end

        if @subscriber.save
          # Update list subscriptions if specified
          if params[:list_ids].present?
            # Remove from lists not in the new list
            @subscriber.list_subscriptions.where.not(list_id: params[:list_ids]).destroy_all

            # Add to new lists
            params[:list_ids].each do |list_id|
              list = current_account.lists.find(list_id)
              list.add_subscriber(@subscriber) unless @subscriber.lists.include?(list)
            end
          end

          render json: {
            subscriber: @subscriber.as_json(include: :list_subscriptions)
          }
        else
          render_unprocessable_entity(@subscriber)
        end
      end

      # DELETE /api/v1/subscribers/:id
      def destroy
        @subscriber = current_account.subscribers.find(params[:id])
        @subscriber.destroy

        head :no_content
      end

      # POST /api/v1/subscribers/:id/unsubscribe
      def unsubscribe
        @subscriber = current_account.subscribers.find(params[:id])
        @subscriber.unsubscribe!

        render json: {
          subscriber: @subscriber.as_json(include: :list_subscriptions),
          message: "Subscriber unsubscribed successfully"
        }
      end

      # POST /api/v1/subscribers/:id/resubscribe
      def resubscribe
        @subscriber = current_account.subscribers.find(params[:id])

        # Can only resubscribe if currently unsubscribed
        if @subscriber.status == "unsubscribed"
          @subscriber.update!(
            status: "active",
            unsubscribed_at: nil
          )

          # Reactivate list subscriptions
          @subscriber.list_subscriptions.where(status: "unsubscribed").update_all(
            status: "active",
            unsubscribed_at: nil
          )

          render json: {
            subscriber: @subscriber.as_json(include: :list_subscriptions),
            message: "Subscriber resubscribed successfully"
          }
        else
          render_error("Subscriber is not unsubscribed", status: :unprocessable_entity)
        end
      end

      private

      def subscriber_params
        params.require(:subscriber).permit(:email, :first_name, :last_name, :status, :source, list_ids: [])
      end
    end
  end
end
