module Api
  module V1
    class TemplatesController < BaseController
      # GET /api/v1/templates
      def index
        @templates = current_account.templates

        # Paginate
        @templates = paginate(@templates)

        render json: {
          templates: @templates.as_json,
          meta: pagination_meta(@templates)
        }
      end

      # GET /api/v1/templates/:id
      def show
        @template = current_account.templates.find(params[:id])

        render json: {
          template: @template.as_json(methods: [:rendered_html])
        }
      end

      # POST /api/v1/templates
      def create
        @template = current_account.templates.build(template_params)

        if @template.save
          render json: {
            template: @template.as_json
          }, status: :created
        else
          render_unprocessable_entity(@template)
        end
      end

      # PATCH/PUT /api/v1/templates/:id
      def update
        @template = current_account.templates.find(params[:id])

        if @template.update(template_params)
          render json: {
            template: @template.as_json
          }
        else
          render_unprocessable_entity(@template)
        end
      end

      # DELETE /api/v1/templates/:id
      def destroy
        @template = current_account.templates.find(params[:id])
        @template.destroy

        head :no_content
      end

      private

      def template_params
        params.require(:template).permit(
          :name,
          :description,
          :html_content,
          :markdown_content,
          :is_default
        )
      end
    end
  end
end
