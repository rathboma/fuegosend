module Api
  module V1
    class BaseController < ApplicationController
      include ApiAuthenticable

      # Rescue from common errors
      rescue_from ActiveRecord::RecordNotFound, with: :record_not_found
      rescue_from ActiveRecord::RecordInvalid, with: :record_invalid
      rescue_from ActionController::ParameterMissing, with: :parameter_missing

      private

      def record_not_found(exception)
        render_not_found(exception.message)
      end

      def record_invalid(exception)
        render_unprocessable_entity(exception.record)
      end

      def parameter_missing(exception)
        render_error("Missing parameter: #{exception.param}", status: :bad_request)
      end

      # Pagination helpers
      def paginate(collection, per_page: 25)
        page = params[:page] || 1
        per = params[:per_page] || per_page

        collection.page(page).per(per)
      end

      def pagination_meta(collection)
        {
          current_page: collection.current_page,
          next_page: collection.next_page,
          prev_page: collection.prev_page,
          total_pages: collection.total_pages,
          total_count: collection.total_count
        }
      end
    end
  end
end
