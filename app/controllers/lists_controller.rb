class ListsController < ApplicationController
  before_action :authenticate_user!
  before_action :set_list, only: [:show, :edit, :update, :destroy]

  # GET /lists
  def index
    @lists = current_account.lists.order(created_at: :desc)
  end

  # GET /lists/:id
  def show
    @subscribers = @list.active_subscribers
                        .order(created_at: :desc)
                        .limit(10)
    @recent_campaigns = @list.campaigns.order(created_at: :desc).limit(5)
  end

  # GET /lists/new
  def new
    @list = current_account.lists.new
  end

  # POST /lists
  def create
    @list = current_account.lists.new(list_params)

    if @list.save
      redirect_to @list, notice: "List was successfully created."
    else
      render :new, status: :unprocessable_entity
    end
  end

  # GET /lists/:id/edit
  def edit
  end

  # PATCH/PUT /lists/:id
  def update
    if @list.update(list_params)
      redirect_to @list, notice: "List was successfully updated."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  # DELETE /lists/:id
  def destroy
    @list.destroy
    redirect_to lists_url, notice: "List was successfully deleted."
  end

  private

  def set_list
    @list = current_account.lists.find(params[:id])
  end

  def list_params
    params.require(:list).permit(
      :name,
      :description,
      :enable_subscription_form,
      :double_opt_in,
      :form_redirect_url,
      :form_success_message
    )
  end

  def current_account
    @current_account ||= current_user.account
  end
  helper_method :current_account
end
