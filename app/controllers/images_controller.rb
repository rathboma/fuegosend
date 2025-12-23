class ImagesController < ApplicationController
  before_action :authenticate_user!

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
