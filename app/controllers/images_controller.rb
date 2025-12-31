class ImagesController < ApplicationController
  before_action :authenticate_user!, only: [:create]

  # GET /i/:slug
  def show
    @image = Image.find_by!(slug: params[:slug])
    redirect_to rails_blob_url(@image.file, disposition: "inline"), allow_other_host: false
  end

  # POST /images
  def create
    @image = current_account.images.new
    @image.file.attach(params[:file])

    if @image.save
      render json: {
        success: true,
        url: @image.url,
        id: @image.id
      }
    else
      render json: {
        success: false,
        errors: @image.errors.full_messages
      }, status: :unprocessable_entity
    end
  end

  private

  def current_account
    @current_account ||= current_user.account
  end
end
