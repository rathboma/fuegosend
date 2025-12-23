module Api
  module V1
    class ApiKeysController < BaseController
      # GET /api/v1/api_keys
      def index
        @api_keys = current_account.api_keys

        # Filter by active status
        if params[:active].present?
          @api_keys = @api_keys.where(active: params[:active])
        end

        # Paginate
        @api_keys = paginate(@api_keys)

        render json: {
          api_keys: @api_keys.as_json(
            only: [:id, :name, :last_4, :last_used_at, :expires_at, :active, :created_at],
            include: {
              user: { only: [:id, :email, :first_name, :last_name] }
            }
          ),
          meta: pagination_meta(@api_keys)
        }
      end

      # GET /api/v1/api_keys/:id
      def show
        @api_key = current_account.api_keys.find(params[:id])

        render json: {
          api_key: @api_key.as_json(
            only: [:id, :name, :last_4, :last_used_at, :expires_at, :active, :created_at],
            include: {
              user: { only: [:id, :email, :first_name, :last_name] }
            }
          )
        }
      end

      # POST /api/v1/api_keys
      def create
        @api_key = current_account.api_keys.build(api_key_params)
        @api_key.user = current_user

        if @api_key.save
          # Return the full token only on creation (it won't be shown again)
          render json: {
            api_key: @api_key.as_json(
              only: [:id, :name, :last_4, :expires_at, :active, :created_at]
            ),
            token: @api_key.token, # Only available on creation
            message: "API key created successfully. Save this token securely - it won't be shown again."
          }, status: :created
        else
          render_unprocessable_entity(@api_key)
        end
      end

      # PATCH/PUT /api/v1/api_keys/:id
      def update
        @api_key = current_account.api_keys.find(params[:id])

        # Only allow updating name and active status
        update_params = params.require(:api_key).permit(:name, :active)

        if @api_key.update(update_params)
          render json: {
            api_key: @api_key.as_json(
              only: [:id, :name, :last_4, :last_used_at, :expires_at, :active, :created_at]
            )
          }
        else
          render_unprocessable_entity(@api_key)
        end
      end

      # DELETE /api/v1/api_keys/:id
      def destroy
        @api_key = current_account.api_keys.find(params[:id])
        @api_key.destroy

        head :no_content
      end

      # POST /api/v1/api_keys/:id/revoke
      def revoke
        @api_key = current_account.api_keys.find(params[:id])
        @api_key.update!(active: false)

        render json: {
          api_key: @api_key.as_json(
            only: [:id, :name, :last_4, :last_used_at, :expires_at, :active, :created_at]
          ),
          message: "API key revoked successfully"
        }
      end

      private

      def api_key_params
        params.require(:api_key).permit(:name, :expires_at)
      end
    end
  end
end
