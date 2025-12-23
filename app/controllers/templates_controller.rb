class TemplatesController < ApplicationController
  before_action :authenticate_user!
  before_action :set_template, only: [:show, :edit, :update, :destroy]

  # GET /templates
  def index
    @templates = current_account.templates.order(created_at: :desc)
  end

  # GET /templates/:id
  def show
    @campaigns_using = @template.campaigns.order(created_at: :desc).limit(10)
  end

  # GET /templates/new
  def new
    @template = current_account.templates.new
  end

  # POST /templates
  def create
    @template = current_account.templates.new(template_params)

    if @template.save
      redirect_to @template, notice: "Template was successfully created."
    else
      render :new, status: :unprocessable_entity
    end
  end

  # GET /templates/:id/edit
  def edit
  end

  # PATCH/PUT /templates/:id
  def update
    if @template.update(template_params)
      redirect_to @template, notice: "Template was successfully updated."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  # DELETE /templates/:id
  def destroy
    if @template.campaigns.exists?
      redirect_to @template, alert: "Cannot delete template that is being used by campaigns."
    else
      @template.destroy
      redirect_to templates_url, notice: "Template was successfully deleted."
    end
  end

  private

  def set_template
    @template = current_account.templates.find(params[:id])
  end

  def template_params
    params.require(:template).permit(
      :name,
      :description,
      :html_content,
      :markdown_content,
      :is_default
    )
  end

  def current_account
    @current_account ||= current_user.account
  end
  helper_method :current_account
end
